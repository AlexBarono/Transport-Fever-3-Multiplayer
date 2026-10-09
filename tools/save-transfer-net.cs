// Background IO for Windows PowerShell 5.1 and PowerShell 7. No game files or UI calls.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace TF3MP {
    public sealed class TransferFile {
        public string Name;
        public string Path;
        public long Length;
        public byte[] Hash;
    }

    public sealed class TransferJob {
        public volatile bool Finished;
        public Exception Error;
        public object Result;
        public int Streams;
        public double Seconds;
        public Task Work;
        private long bytes, firstByte, lastByte;
        private volatile bool cancelled;
        private readonly object gate = new object();
        private readonly List<IDisposable> handles = new List<IDisposable>();
        private Exception laneError;
        public long Bytes { get { return Interlocked.Read(ref bytes); } }

        private void Track(IDisposable handle) {
            lock (gate) {
                if (cancelled) { handle.Dispose(); throw new OperationCanceledException(); }
                handles.Add(handle);
            }
        }
        public void Cancel() {
            lock (gate) {
                cancelled = true;
                foreach (IDisposable handle in handles) { try { handle.Dispose(); } catch {} }
            }
        }
        private void Check() {
            if (laneError != null) throw laneError;
            if (cancelled) throw new OperationCanceledException();
        }
        private void Progress(int count) {
            long now = Stopwatch.GetTimestamp();
            Interlocked.CompareExchange(ref firstByte, now, 0);
            Interlocked.Exchange(ref lastByte, now);
            Interlocked.Add(ref bytes, count);
        }
        private void Start(Action action) {
            Work = Task.Run(() => {
                try { action(); }
                catch (Exception e) { Error = Unwrap(e); Cancel(); }
                finally {
                    Seconds = firstByte == 0 ? 0 : Math.Max(0.001, (lastByte - firstByte) / (double)Stopwatch.Frequency);
                    Finished = true;
                }
            });
        }
        private static Exception Unwrap(Exception e) {
            while (e is AggregateException && e.InnerException != null) e = e.InnerException;
            return e;
        }
        private Task Lane(Action action) {
            return Task.Run(() => {
                try { action(); }
                catch (Exception e) {
                    lock (gate) { if (laneError == null) laneError = Unwrap(e); }
                    Cancel();
                    throw;
                }
            });
        }
        private static byte[] ReadExact(Stream stream, int count) {
            byte[] data = new byte[count];
            int at = 0;
            while (at < count) {
                int n = stream.Read(data, at, count - at);
                if (n == 0) throw new EndOfStreamException("Die Gegenstelle hat die Verbindung getrennt.");
                at += n;
            }
            return data;
        }
        private static string ReadText(Stream stream, int maxBytes) {
            uint length = 0;
            for (int shift = 0; shift <= 28; shift += 7) {
                int b = stream.ReadByte();
                if (b < 0) throw new EndOfStreamException("Unvollständige Übertragungsdaten.");
                if (shift == 28 && (b & 0xf8) != 0) throw new InvalidDataException("Ungültige Textlänge.");
                length |= (uint)(b & 127) << shift;
                if ((b & 128) == 0) {
                    if (length > maxBytes) throw new InvalidDataException("Übertragungstext zu lang.");
                    return new UTF8Encoding(false, true).GetString(ReadExact(stream, (int)length));
                }
            }
            throw new InvalidDataException("Ungültige Textlänge.");
        }
        public static TransferJob Read(BinaryReader reader, string kind, int length) {
            TransferJob job = new TransferJob();
            job.Track(reader.BaseStream);
            job.Start(() => {
                if (kind == "text") job.Result = ReadText(reader.BaseStream, length);
                else if (kind == "bytes") job.Result = ReadExact(reader.BaseStream, length);
                else if (kind == "byte") job.Result = ReadExact(reader.BaseStream, 1)[0];
                else if (kind == "int") job.Result = BitConverter.ToInt32(ReadExact(reader.BaseStream, 4), 0);
                else if (kind == "long") job.Result = BitConverter.ToInt64(ReadExact(reader.BaseStream, 8), 0);
                else throw new ArgumentException("Unknown transfer header type.");
            });
            return job;
        }
        public static TransferJob Hash(string path) {
            TransferJob job = new TransferJob();
            job.Start(() => {
                using (FileStream file = File.OpenRead(path))
                using (SHA256 sha = SHA256.Create()) {
                    job.Track(file);
                    byte[] buffer = new byte[1024 * 1024];
                    int n;
                    while ((n = file.Read(buffer, 0, buffer.Length)) > 0) {
                        job.Check(); sha.TransformBlock(buffer, 0, n, null, 0); job.Progress(n);
                    }
                    sha.TransformFinalBlock(buffer, 0, 0); job.Result = sha.Hash;
                }
            });
            return job;
        }
        public static TransferJob Write(Stream stream, byte[] buffer, int offset, int count) {
            TransferJob job = new TransferJob();
            job.Track(stream);
            job.Start(() => stream.Write(buffer, offset, count));
            return job;
        }
        private static void Configure(TcpClient client) {
            client.NoDelay = true;
            client.SendBufferSize = client.ReceiveBufferSize = 8 * 1024 * 1024;
            client.SendTimeout = 30000; client.ReceiveTimeout = 60000;
        }
        private static long Offset(long length, int slot, int streams) { return length * slot / streams; }
        private void SendLane(TcpClient client, TransferFile[] files, int slot, int streams) {
            byte[] buffer = new byte[256 * 1024];
            using (client) {
                Stream stream = client.GetStream();
                foreach (TransferFile spec in files) {
                    using (FileStream file = File.OpenRead(spec.Path)) {
                        Track(file);
                        long start = Offset(spec.Length, slot, streams), left = Offset(spec.Length, slot + 1, streams) - start;
                        if (file.Length != spec.Length) throw new InvalidDataException("Der angebotene Spielstand wurde während der Übertragung geändert.");
                        file.Position = start;
                        int pending = 0;
                        while (left > 0) {
                            Check();
                            int n = file.Read(buffer, 0, (int)Math.Min(left, Math.Min(buffer.Length, 1024 * 1024 - pending)));
                            if (n == 0) throw new EndOfStreamException("Der angebotene Spielstand ist unvollständig.");
                            Interlocked.CompareExchange(ref firstByte, Stopwatch.GetTimestamp(), 0);
                            stream.Write(buffer, 0, n); left -= n; pending += n;
                            // Bound outstanding data and measure delivered bytes, not Windows'
                            // potentially much larger buffered Write() completions.
                            if (pending >= 1024 * 1024 || left == 0) {
                                if (stream.ReadByte() != 1) throw new IOException("Eine Datenverbindung wurde nicht bestätigt.");
                                Progress(pending); pending = 0;
                            }
                        }
                    }
                }
                // Confirm EOF as well as expected bytes, so excess lane data is rejected.
                client.Client.Shutdown(SocketShutdown.Send);
            }
        }
        public static TransferJob Send(TcpListener listener, IPAddress peer, string token, TransferFile[] files, int streams) {
            if (streams < 2 || streams > 4) throw new ArgumentOutOfRangeException("streams");
            TransferJob job = new TransferJob();
            job.Start(() => {
                Task[] tasks = new Task[streams];
                Stopwatch waiting = Stopwatch.StartNew(); int accepted = 0, rejected = 0;
                while (accepted < streams) {
                    job.Check();
                    if (waiting.Elapsed.TotalSeconds > 15) throw new IOException("Die zusätzlichen Datenverbindungen fehlen. VPN oder Firewall prüfen.");
                    if (!listener.Pending()) { Thread.Sleep(10); continue; }
                    TcpClient client = listener.AcceptTcpClient(); job.Track(client); Configure(client);
                    client.ReceiveTimeout = 1000;
                    try {
                        if (!((IPEndPoint)client.Client.RemoteEndPoint).Address.Equals(peer)) throw new InvalidDataException();
                        Stream stream = client.GetStream();
                        if (ReadText(stream, 32) != "TF3MPRANGE1" || ReadText(stream, 64) != token) throw new InvalidDataException();
                        int slot = BitConverter.ToInt32(ReadExact(stream, 4), 0);
                        if (slot < 0 || slot >= streams || tasks[slot] != null) throw new InvalidDataException();
                        client.ReceiveTimeout = 60000;
                        int lane = slot;
                        tasks[slot] = job.Lane(() => job.SendLane(client, files, lane, streams));
                        accepted++; job.Streams = accepted;
                    } catch (Exception e) {
                        if (!(e is IOException) && !(e is SocketException) && !(e is InvalidDataException)) throw;
                        client.Close();
                        if (++rejected > 16) throw new IOException("Zu viele ungültige Datenverbindungen.");
                    }
                }
                Task.WaitAll(tasks);
            });
            return job;
        }
        private void ReceiveLane(string host, int port, string token, TransferFile[] files, int slot, int streams) {
            TcpClient client = new TcpClient(); Track(client); Configure(client);
            using (client) {
                IAsyncResult connecting = client.BeginConnect(host, port, null, null);
                try {
                    Stopwatch wait = Stopwatch.StartNew();
                    while (!connecting.AsyncWaitHandle.WaitOne(100)) { Check(); if (wait.Elapsed.TotalSeconds >= 15) throw new IOException("Zeitüberschreitung beim Öffnen einer Datenverbindung."); }
                    client.EndConnect(connecting);
                } finally { connecting.AsyncWaitHandle.Close(); }
                Stream stream = client.GetStream();
                BinaryWriter writer = new BinaryWriter(stream, Encoding.UTF8);
                writer.Write("TF3MPRANGE1"); writer.Write(token); writer.Write(slot); writer.Flush();
                Interlocked.Increment(ref Streams);
                byte[] buffer = new byte[256 * 1024];
                foreach (TransferFile spec in files) {
                    using (FileStream file = new FileStream(spec.Path, FileMode.Open, FileAccess.Write, FileShare.ReadWrite)) {
                        Track(file);
                        long start = Offset(spec.Length, slot, streams), left = Offset(spec.Length, slot + 1, streams) - start;
                        file.Position = start;
                        int pending = 0;
                        while (left > 0) {
                            Check();
                            int n = stream.Read(buffer, 0, (int)Math.Min(left, Math.Min(buffer.Length, 1024 * 1024 - pending)));
                            if (n == 0) throw new EndOfStreamException("Eine Datenverbindung wurde vorzeitig getrennt.");
                            file.Write(buffer, 0, n); left -= n; Progress(n); pending += n;
                            if (pending >= 1024 * 1024 || left == 0) {
                                stream.WriteByte(1); pending = 0;
                            }
                        }
                    }
                }
                if (stream.ReadByte() != -1) throw new InvalidDataException("Überzählige Daten auf einer Datenverbindung.");
            }
        }
        public static TransferJob Receive(string host, int port, string token, TransferFile[] files, int streams) {
            if (streams < 2 || streams > 4) throw new ArgumentOutOfRangeException("streams");
            TransferJob job = new TransferJob();
            job.Start(() => {
                foreach (TransferFile spec in files) {
                    job.Check();
                    using (FileStream file = File.Create(spec.Path)) { file.SetLength(spec.Length); }
                }
                Task[] tasks = new Task[streams];
                for (int i = 0; i < streams; i++) { int slot = i; tasks[i] = job.Lane(() => job.ReceiveLane(host, port, token, files, slot, streams)); }
                try { Task.WaitAll(tasks); }
                finally { foreach (Task task in tasks) { try { task.Wait(2000); } catch {} } }
                foreach (TransferFile spec in files) {
                    job.Check();
                    using (FileStream file = File.OpenRead(spec.Path))
                    using (SHA256 sha = SHA256.Create()) {
                        job.Track(file);
                        byte[] buffer = new byte[1024 * 1024]; int n;
                        while ((n = file.Read(buffer, 0, buffer.Length)) > 0) { job.Check(); sha.TransformBlock(buffer, 0, n, null, 0); }
                        sha.TransformFinalBlock(buffer, 0, 0);
                        byte[] actual = sha.Hash;
                        if (actual.Length != spec.Hash.Length) throw new IOException("Datei-Fingerabdruck fehlt.");
                        for (int i = 0; i < actual.Length; i++) if (actual[i] != spec.Hash[i]) throw new IOException("Die Datei '" + spec.Name + "' kam beschädigt an.");
                    }
                }
            });
            return job;
        }
    }
}
