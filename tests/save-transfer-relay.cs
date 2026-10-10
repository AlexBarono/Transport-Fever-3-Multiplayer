// Test-only TCP relay. Delay receipt packets to model VPN latency without changing
// the production transfer code or contacting another computer.
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public sealed class TF3MPReceiptRelay : IDisposable {
    private readonly TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
    private readonly List<TcpClient> sockets = new List<TcpClient>();
    private readonly object gate = new object();
    public readonly Task Work;
    public int Port { get { return ((IPEndPoint)listener.LocalEndpoint).Port; } }
    private static Task Run(Action action) {
        return Task.Factory.StartNew(action, CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
    }
    public TF3MPReceiptRelay(int destinationPort, int lanes, int delayMs) {
        listener.Start();
        Work = Run(() => {
            Task[] tasks = new Task[lanes];
            for (int i = 0; i < lanes; i++) {
                TcpClient downstream = listener.AcceptTcpClient();
                TcpClient upstream = new TcpClient(); upstream.Connect(IPAddress.Loopback, destinationPort);
                downstream.NoDelay = upstream.NoDelay = true;
                lock (gate) { sockets.Add(downstream); sockets.Add(upstream); }
                tasks[i] = Run(() => {
                    using (downstream) using (upstream) {
                        Stream fromReceiver = downstream.GetStream(), fromSender = upstream.GetStream();
                        BinaryReader reader = new BinaryReader(fromReceiver, Encoding.UTF8);
                        BinaryWriter writer = new BinaryWriter(fromSender, Encoding.UTF8);
                        writer.Write(reader.ReadString()); writer.Write(reader.ReadString()); writer.Write(reader.ReadInt32()); writer.Flush();
                        Task receipts = Run(() => {
                            byte[] packet = new byte[4096]; int count;
                            while ((count = fromReceiver.Read(packet, 0, packet.Length)) > 0) {
                                Thread.Sleep(delayMs); fromSender.Write(packet, 0, count);
                            }
                            upstream.Client.Shutdown(SocketShutdown.Send);
                        });
                        fromSender.CopyTo(fromReceiver, 256 * 1024);
                        downstream.Client.Shutdown(SocketShutdown.Send);
                        receipts.Wait();
                    }
                });
            }
            Task.WaitAll(tasks);
        });
    }
    public void Dispose() {
        listener.Stop();
        lock (gate) { foreach (TcpClient socket in sockets) socket.Close(); }
        try { Work.Wait(3000); } catch {}
    }
}
