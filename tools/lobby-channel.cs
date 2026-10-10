using System;
using System.Collections.Concurrent;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace TF3MP {
    // Owns the already verified save-transfer connection. No additional listening port.
    public sealed class LobbyChannel : IDisposable {
        readonly TcpClient client;
        readonly NetworkStream stream;
        readonly string session;
        readonly bool host;
        readonly object writeGate = new object();
        readonly ConcurrentQueue<string> messages = new ConcurrentQueue<string>();
        readonly Timer heartbeat;
        long lastReceived = DateTime.UtcNow.Ticks;
        volatile bool connected = true;
        volatile string error = "";
        public bool Connected { get { return connected; } }
        public string Error { get { return error; } }

        public LobbyChannel(TcpClient connection, string sessionId, bool isHost) {
            if (connection == null || !System.Text.RegularExpressions.Regex.IsMatch(sessionId ?? "", "^[a-f0-9]{32}$"))
                throw new ArgumentException("Invalid lobby connection/session");
            client = connection; session = sessionId; host = isHost;
            client.NoDelay = true; client.ReceiveTimeout = 0; client.SendTimeout = 5000;
            stream = client.GetStream();
            heartbeat = new Timer(Pulse, null, 3000, 3000);
            new Thread(Read) { IsBackground = true, Name = "TF3MP lobby" }.Start();
        }
        static bool ValidId(string value) {
            return System.Text.RegularExpressions.Regex.IsMatch(value ?? "", "^[a-f0-9]{32}$");
        }
        bool Allowed(string command, string argument, bool fromHost) {
            if (command == "PING" || command == "PONG" || command == "READY") return argument == "" && (command != "READY" || !fromHost);
            if (command == "START" || command == "RESYNC") return fromHost && ValidId(argument);
            if (command == "STARTED") return !fromHost && ValidId(argument);
            if (command == "ERROR") return argument.Length <= 800 && argument.IndexOfAny(new char[] {'\r','\n','|'}) < 0;
            return false;
        }
        public void Send(string command, string argument) {
            argument = argument ?? "";
            if (!Allowed(command, argument, host)) throw new ArgumentException("Invalid lobby command");
            try {
                lock (writeGate) {
                    if (!connected) throw new IOException("Lobby connection closed");
                    byte[] bytes = Encoding.UTF8.GetBytes(session + "|" + command + "|" + argument);
                    byte[] length = BitConverter.GetBytes(bytes.Length);
                    stream.Write(length, 0, length.Length); stream.Write(bytes, 0, bytes.Length); stream.Flush();
                }
            } catch (Exception ex) { Fail(ex.Message); throw; }
        }
        public string Take() { string value; return messages.TryDequeue(out value) ? value : null; }
        void Read() {
            try {
                using (BinaryReader reader = new BinaryReader(stream, new UTF8Encoding(false, true), true)) {
                    while (connected) {
                        int length = reader.ReadInt32();
                        if (length < 35 || length > 1024) throw new IOException("Invalid lobby frame");
                        byte[] data = reader.ReadBytes(length);
                        if (data.Length != length) throw new EndOfStreamException("Lobby disconnected");
                        string[] parts = new UTF8Encoding(false, true).GetString(data).Split('|');
                        if (parts.Length != 3 || parts[0] != session || !Allowed(parts[1], parts[2], !host))
                            throw new IOException("Invalid lobby message/session");
                        Interlocked.Exchange(ref lastReceived, DateTime.UtcNow.Ticks);
                        if (parts[1] == "PING") { Send("PONG", ""); continue; }
                        if (parts[1] == "PONG") continue;
                        if (messages.Count >= 64) throw new IOException("Lobby queue full");
                        messages.Enqueue(parts[1] + "|" + parts[2]);
                    }
                }
            } catch (Exception ex) { if (connected) Fail(ex.Message); }
        }
        void Pulse(object unused) {
            try {
                if (DateTime.UtcNow.Ticks - Interlocked.Read(ref lastReceived) > TimeSpan.FromSeconds(20).Ticks) { Fail("Lobby timeout"); return; }
                if (connected) Send("PING", "");
            } catch { }
        }
        void Fail(string message) { error = message; connected = false; client.Close(); }
        public void Dispose() { connected = false; heartbeat.Dispose(); client.Close(); }
    }

    public sealed class LobbyProgress {
        public volatile bool Cancel;
        readonly object gate = new object();
        string text = "Warte auf Spielstand vom Gastgeber";
        long done, total;
        public void Publish(string value, long bytes, long size) { lock (gate) { text = value; done = bytes; total = size; } }
        public object[] Snapshot() { lock (gate) { return new object[] { text, done, total }; } }
    }
}
