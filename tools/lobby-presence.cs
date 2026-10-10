using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace TF3MP {
    // The same local TCP port changes from rendezvous to save transfer. No extra router port.
    public sealed class LobbyPresence : IDisposable {
        readonly TcpListener listener;
        readonly object gate = new object();
        TcpClient peer;
        volatile bool running = true, connected;
        volatile bool transferring;
        readonly ManualResetEvent transferReady = new ManualResetEvent(false);
        volatile string error = "";
        public bool Connected { get { return connected; } }
        public string Error { get { return error; } }
        public LobbyPresence(int port) {
            try {
                listener = new TcpListener(IPAddress.IPv6Any, port);
                listener.Server.DualMode = true; listener.Start(4);
            } catch {
                if (listener != null) listener.Stop();
                listener = new TcpListener(IPAddress.Any, port); listener.Start(4);
            }
            new Thread(Run) { IsBackground = true, Name = "TF3MP waiting room" }.Start();
        }
        void Run() {
            while (running) {
                TcpClient candidate = null;
                try {
                    candidate = listener.AcceptTcpClient();
                    candidate.ReceiveTimeout = 5000; candidate.SendTimeout = 5000; candidate.NoDelay = true;
                    lock (gate) { if (!running) { candidate.Close(); return; } peer = candidate; }
                    var reader = new BinaryReader(candidate.GetStream(), Encoding.ASCII, true);
                    var writer = new BinaryWriter(candidate.GetStream(), Encoding.ASCII, true);
                    if (reader.ReadInt32() != 0x354c504d) throw new IOException("Launcher v53 required");
                    lock (gate) { writer.Write(0x354c504d); writer.Flush(); connected = true; error = ""; }
                    while (running) {
                        if (reader.ReadByte() != 1) throw new IOException("Invalid waiting-room heartbeat");
                        bool sendTransfer;
                        lock (gate) { if (!running) return; sendTransfer = transferring; writer.Write((byte)(sendTransfer ? 2 : 1)); writer.Flush(); }
                        if (sendTransfer) {
                            if (reader.ReadByte() != 2) throw new IOException("Transfer acknowledgement missing");
                            running = false; listener.Stop(); transferReady.Set(); return;
                        }
                    }
                } catch (Exception ex) { if (running) error = ex.Message; }
                finally { lock (gate) { connected = false; if (candidate != null) candidate.Close(); if (peer == candidate) peer = null; } }
            }
        }
        public void BeginTransfer() {
            lock (gate) {
                if (!running || !connected || peer == null) throw new IOException("Mitspieler nicht mehr verbunden");
                transferring = true;
            }
            if (!transferReady.WaitOne(7000)) throw new IOException("Mitspieler hat die Übertragung nicht bestätigt");
        }
        public static void WaitForTransfer(string address, int port, LobbyProgress progress) {
            while (!progress.Cancel) {
                using (var client = new TcpClient()) {
                    try {
                        var attempt = client.BeginConnect(address, port, null, null);
                        DateTime deadline = DateTime.UtcNow.AddSeconds(5);
                        while (!attempt.AsyncWaitHandle.WaitOne(100)) { if (progress.Cancel) throw new OperationCanceledException(); if (DateTime.UtcNow > deadline) throw new IOException("Connection timeout"); }
                        client.EndConnect(attempt); client.ReceiveTimeout = 5000; client.SendTimeout = 5000;
                        var reader = new BinaryReader(client.GetStream(), Encoding.ASCII, true);
                        var writer = new BinaryWriter(client.GetStream(), Encoding.ASCII, true);
                        writer.Write(0x354c504d); writer.Flush();
                        if (reader.ReadInt32() != 0x354c504d) throw new IOException("Beide PCs brauchen Launcher v53");
                        progress.Publish("Verbunden. Warte auf Spielstand vom Gastgeber", 0, 0);
                        while (!progress.Cancel) {
                            writer.Write((byte)1); writer.Flush();
                            byte result = reader.ReadByte();
                            if (result == 2) { writer.Write((byte)2); writer.Flush(); return; }
                            if (result != 1) throw new IOException("Invalid waiting-room response");
                            for (int n = 0; n < 10 && !progress.Cancel; n++) Thread.Sleep(100);
                        }
                    } catch (OperationCanceledException) { throw; }
                    catch { progress.Publish("Warte auf Verbindung zum Gastgeber", 0, 0); }
                }
                for (int n = 0; n < 10 && !progress.Cancel; n++) Thread.Sleep(100);
            }
            throw new OperationCanceledException("Abgebrochen.");
        }
        public void Dispose() { lock (gate) { running = false; connected = false; listener.Stop(); if (peer != null) peer.Close(); peer = null; } }
    }
}
