// Internet transport for the existing IPv4 loopback bridge. No Steam identity or
// public relay is assumed. TLS pins and random invitation keys are never logged.
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace TF3MP.Internet {
    internal sealed class HostNotReadyException : IOException { }
    public sealed class Tunnel : IDisposable {
        private volatile bool stopped;
        private TcpListener listener;
        private UdpClient localUdp;
        private UdpClient hostUdp;
        private readonly object gate = new object(), writeGate = new object();
        private readonly List<TcpClient> sockets = new List<TcpClient>();
        private SslStream udpStream;
        private IPEndPoint gameEndpoint;
        private X509Certificate2 certificate;
        private string host, pin, secret;
        private int remotePort, localPort, udpActive;
        private long tcpBytes, udpPackets, rejected, reconnects;
        private long accepted;
        private long clearConnections, tlsConnections;
        private bool encryptTcp;
        public long ClearConnections { get { return Interlocked.Read(ref clearConnections); } }
        public long TlsConnections { get { return Interlocked.Read(ref tlsConnections); } }
        public bool SaveEncrypted { get { return encryptTcp; } }
        public string InvitationId { get { return Hash(Encoding.ASCII.GetBytes(secret)).Substring(0,12); } }
        public long Accepted { get { return Interlocked.Read(ref accepted); } }
        private string lastError = "";
        public bool Running { get { return !stopped && listener != null; } }
        public bool SupportsIPv6 { get { return listener != null && ((IPEndPoint)listener.LocalEndpoint).AddressFamily == AddressFamily.InterNetworkV6; } }
        public int Port { get; private set; }
        public int PublicPort { get { return remotePort==0 ? Port : remotePort; } }
        public string Fingerprint { get { return pin; } }
        public string Key { get { return secret; } }
        public string LastError { get { lock(gate) return lastError; } }
        public long TcpBytes { get { return Interlocked.Read(ref tcpBytes); } }
        public long UdpPackets { get { return Interlocked.Read(ref udpPackets); } }
        public long Rejected { get { return Interlocked.Read(ref rejected); } }
        public long Reconnects { get { return Interlocked.Read(ref reconnects); } }
        public bool GameChannelConnected { get { return Volatile.Read(ref udpActive) != 0; } }

        public static string Hash(byte[] bytes) {
            using (SHA256 sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant();
        }
        private static string NewKey() {
            byte[] bytes = new byte[32]; using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(bytes);
            return BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant();
        }
        private static X509Certificate2 NewCertificate() {
            using (RSA rsa = RSA.Create()) {
                rsa.KeySize = 2048;
                CertificateRequest req = new CertificateRequest("CN=TF3MP invitation", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
                using (X509Certificate2 cert = req.CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-5), DateTimeOffset.UtcNow.AddDays(2)))
                    // .NET Framework SChannel cannot authenticate with EphemeralKeySet.
                    // Import a user key without PersistKeySet; Dispose deletes its container.
                    return new X509Certificate2(cert.Export(X509ContentType.Pfx), "", X509KeyStorageFlags.UserKeySet);
            }
        }
        private static void Background(ThreadStart action) { Thread t = new Thread(action); t.IsBackground = true; t.Start(); }
        private void Error(Exception e) { if (!stopped) lock(gate) lastError = e.GetType().Name + ": " + e.Message; }
        private bool Track(TcpClient c) {
            lock(gate) { if(stopped || sockets.Count >= 16) { c.Close(); Interlocked.Increment(ref rejected); return false; } sockets.Add(c); return true; }
        }
        private void Forget(TcpClient c) { lock(gate) sockets.Remove(c); c.Close(); }
        private static TcpListener Listen(IPAddress address, int port, bool dual) {
            TcpListener l = new TcpListener(address, port);
            l.Server.ExclusiveAddressUse = true;
            if(dual) l.Server.DualMode = true;
            l.Start(16); return l;
        }
        public static Tunnel StartHost(int publicPort, int gamePort) {
            if(publicPort!=0 && publicPort==gamePort) throw new ArgumentException("Internet and game ports must differ");
            Tunnel t = new Tunnel(); t.localPort = gamePort;
            try {
                t.certificate = NewCertificate(); t.pin = Hash(t.certificate.RawData); t.secret = NewKey();
                try { t.listener = Listen(IPAddress.IPv6Any, publicPort, true); }
                catch(SocketException e) {
                    if(e.SocketErrorCode!=SocketError.AddressFamilyNotSupported && e.SocketErrorCode!=SocketError.ProtocolNotSupported && e.SocketErrorCode!=SocketError.AddressNotAvailable) throw;
                    t.listener = Listen(IPAddress.Any, publicPort, false);
                }
                t.Port = ((IPEndPoint)t.listener.LocalEndpoint).Port;
                t.hostUdp = new UdpClient(0);
                if(((IPEndPoint)t.hostUdp.Client.LocalEndPoint).Port==gamePort) {
                    UdpClient occupied=t.hostUdp; t.hostUdp=new UdpClient(0); occupied.Close();
                }
                t.hostUdp.Connect(IPAddress.Loopback,gamePort); t.hostUdp.Client.ReceiveTimeout=1000;
                Background(t.HostAccept); return t;
            } catch { t.Dispose(); throw; }
        }
        public static Tunnel StartClient(string address, int publicPort, string fingerprint, string key, int gamePort) {
            return StartClient(address,publicPort,fingerprint,key,gamePort,false);
        }
        public static Tunnel StartClient(string address, int publicPort, string fingerprint, string key, int gamePort, bool encryptSaves) {
            IPAddress parsed = IPAddress.Parse(address);
            if (fingerprint.Length != 64 || key.Length != 64) throw new ArgumentException("Invalid invitation");
            Tunnel t = new Tunnel(); t.host = parsed.ToString(); t.remotePort = publicPort; t.pin = fingerprint; t.secret = key; t.localPort = gamePort; t.encryptTcp=encryptSaves;
            try {
                t.listener = Listen(IPAddress.Loopback, gamePort, false);
                t.localUdp = new UdpClient(AddressFamily.InterNetwork); t.localUdp.Client.ExclusiveAddressUse=true;
                t.localUdp.Client.Bind(new IPEndPoint(IPAddress.Loopback,gamePort)); t.localUdp.Client.ReceiveTimeout = 1000;
                t.Port = ((IPEndPoint)t.listener.LocalEndpoint).Port;
                Background(t.ClientAccept); Background(t.ClientUdpSend); Background(t.ClientUdpConnect); return t;
            } catch { t.Dispose(); throw; }
        }
        private static void Configure(TcpClient c) {
            c.NoDelay = true; c.SendTimeout = 15000; c.ReceiveTimeout = 7000;
            c.SendBufferSize = 1024 * 1024; c.ReceiveBufferSize = 1024 * 1024;
        }
        private static string ReadLine(Stream s) {
            byte[] buf = new byte[160]; int n = 0;
            while(n < buf.Length) { int b = s.ReadByte(); if(b < 0) throw new EndOfStreamException(); if(b == 10) return Encoding.ASCII.GetString(buf,0,n); buf[n++] = (byte)b; }
            throw new IOException("Handshake too long");
        }
        private static void Line(Stream s, string value) { byte[] b = Encoding.ASCII.GetBytes(value + "\n"); s.Write(b,0,b.Length); }
        private static bool EqualKey(string a, string b) {
            if(a.Length != b.Length) return false; int diff = 0; for(int i=0;i<a.Length;i++) diff |= a[i] ^ b[i]; return diff == 0;
        }
        private string Mac(string role, string clientNonce, string hostNonce) {
            using(HMACSHA256 hmac=new HMACSHA256(Encoding.ASCII.GetBytes(secret)))
                return BitConverter.ToString(hmac.ComputeHash(Encoding.ASCII.GetBytes("TF3MP-PLAIN/1|TCP|"+role+"|"+clientNonce+"|"+hostNonce+"|"+pin))).Replace("-","").ToLowerInvariant();
        }
        private static bool Nonce(string value) {
            if(value.Length!=64) return false;
            foreach(char ch in value) if(!((ch>='0' && ch<='9') || (ch>='a' && ch<='f'))) return false;
            return true;
        }
        // Save bytes use raw TCP. Fresh challenges authenticate both ends without
        // putting the invitation key on the wire or accepting replayed handshakes.
        private Stream ConnectPlain(out TcpClient c) {
            IPAddress ip=IPAddress.Parse(host); c=new TcpClient(ip.AddressFamily); Configure(c);
            if(!Track(c)) throw new IOException("Tunnel closed or full");
            try {
                IAsyncResult pending=c.BeginConnect(ip,remotePort,null,null);
                try { if(!pending.AsyncWaitHandle.WaitOne(6000)) throw new IOException("Internet endpoint unreachable (router/firewall/IPv6)"); c.EndConnect(pending); }
                finally { pending.AsyncWaitHandle.Close(); }
                NetworkStream stream=c.GetStream(); stream.ReadTimeout=stream.WriteTimeout=7000;
                string clientNonce=NewKey(); Line(stream,"TF3MP-PLAIN/1"); Line(stream,clientNonce);
                string hostNonce=ReadLine(stream), proof=ReadLine(stream);
                if(!Nonce(hostNonce) || !EqualKey(proof,Mac("host",clientNonce,hostNonce))) throw new AuthenticationException("Invitation refused (host proof)");
                Line(stream,Mac("client",clientNonce,hostNonce));
                string response=ReadLine(stream);
                if(response=="WAIT") throw new HostNotReadyException();
                if(response!="OK") throw new AuthenticationException("Invitation refused");
                stream.ReadTimeout=Timeout.Infinite; stream.WriteTimeout=15000;
                Interlocked.Increment(ref clearConnections); lock(gate) lastError=""; return stream;
            } catch { Forget(c); throw; }
        }
        private void HostPlain(TcpClient c) {
            NetworkStream stream=c.GetStream(); stream.ReadTimeout=stream.WriteTimeout=7000;
            if(ReadLine(stream)!="TF3MP-PLAIN/1") throw new AuthenticationException("Invalid save handshake");
            string clientNonce=ReadLine(stream); if(!Nonce(clientNonce)) throw new AuthenticationException("Invalid save challenge");
            string hostNonce=NewKey(); Line(stream,hostNonce); Line(stream,Mac("host",clientNonce,hostNonce));
            if(!EqualKey(ReadLine(stream),Mac("client",clientNonce,hostNonce))) { Interlocked.Increment(ref rejected); throw new AuthenticationException("Invitation key refused"); }
            using(TcpClient target=new TcpClient()) {
                Configure(target);
                try { target.Connect(IPAddress.Loopback,localPort); }
                catch(SocketException e) { if(e.SocketErrorCode!=SocketError.ConnectionRefused) throw; Line(stream,"WAIT"); return; }
                if(!Track(target)) return;
                try { Line(stream,"OK"); Interlocked.Increment(ref clearConnections); lock(gate) lastError=""; PipePlain(target,stream,c.Client); }
                finally { Forget(target); }
            }
        }
        private SslStream Connect(string route, out TcpClient c) {
            IPAddress ip = IPAddress.Parse(host); c = new TcpClient(ip.AddressFamily); Configure(c);
            if(!Track(c)) throw new IOException("Tunnel closed or full");
            try {
                IAsyncResult connect = c.BeginConnect(ip, remotePort, null, null);
                try { if(!connect.AsyncWaitHandle.WaitOne(6000)) throw new IOException("Internet endpoint unreachable (router/firewall/IPv6)"); c.EndConnect(connect); }
                finally { connect.AsyncWaitHandle.Close(); }
                SslStream ssl = new SslStream(c.GetStream(), false, delegate(object sender, X509Certificate cert, X509Chain chain, SslPolicyErrors errors) { return cert != null && EqualKey(Hash(cert.GetRawCertData()), pin); });
                ssl.ReadTimeout = ssl.WriteTimeout = 7000;
                try {
                    ssl.AuthenticateAsClient("TF3MP invitation", null, SslProtocols.Tls12, false);
                    Line(ssl,"TF3MP-TLS/1"); Line(ssl,secret); Line(ssl,route);
                    string response=ReadLine(ssl);
                    if(response=="WAIT") throw new HostNotReadyException();
                    if(response!="OK") throw new AuthenticationException("Invitation refused");
                    ssl.ReadTimeout = Timeout.Infinite; ssl.WriteTimeout = 15000;
                    return ssl;
                } catch { ssl.Dispose(); throw; }
            } catch { Forget(c); throw; }
        }
        public static void Probe(string address, int port, string fingerprint, string key) {
            using(Tunnel t = new Tunnel()) { t.host=address; t.remotePort=port; t.pin=fingerprint; t.secret=key;
                TcpClient c; using(SslStream ssl = t.Connect("PROBE",out c)) { ssl.ReadTimeout=7000; if(ReadLine(ssl)!="READY") throw new IOException("Probe failed"); } t.Forget(c);
            }
        }
        public static Task ProbeAsync(string address, int port, string fingerprint, string key) {
            return Task.Factory.StartNew(delegate { Probe(address,port,fingerprint,key); }, CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
        }
        private void HostAccept() {
            while(!stopped) try { TcpClient c = listener.AcceptTcpClient(); Interlocked.Increment(ref accepted); if(Track(c)) Background(delegate { HostConnection(c); }); }
            catch(Exception e) { Error(e); if(!stopped) Thread.Sleep(200); }
        }
        private void HostConnection(TcpClient c) {
            SslStream ssl = null; bool ownsUdp = false;
            string stage="TLS authentication";
            try {
                Configure(c);
                byte[] first=new byte[1]; if(c.Client.Receive(first,0,1,SocketFlags.Peek)==0) return;
                if(first[0]==(byte)'T') { stage="plain TCP authentication/transfer"; HostPlain(c); return; }
                ssl = new SslStream(c.GetStream(), false); ssl.ReadTimeout=ssl.WriteTimeout=7000;
                ssl.AuthenticateAsServer(certificate, false, SslProtocols.Tls12, false);
                stage="invitation authentication";
                if(ReadLine(ssl)!="TF3MP-TLS/1" || !EqualKey(ReadLine(ssl),secret)) { Interlocked.Increment(ref rejected); Error(new IOException("Invitation key refused")); return; }
                string route = ReadLine(ssl);
                stage=route;
                if(route=="PROBE") { Line(ssl,"OK"); Line(ssl,"READY"); return; }
                if(route=="UDP") {
                    if(Interlocked.CompareExchange(ref udpActive,1,0)!=0) { Interlocked.Increment(ref rejected); Error(new IOException("Game channel already in use")); return; }
                    ownsUdp=true; lock(gate) lastError=""; Line(ssl,"OK"); ssl.ReadTimeout=15000; HostUdp(ssl);
                } else if(route=="TCP") {
                    using(TcpClient target = new TcpClient()) {
                        // Only this fixed loopback destination is reachable, never an arbitrary proxy.
                        Configure(target);
                        try { target.Connect(IPAddress.Loopback,localPort); }
                        catch(SocketException e) { if(e.SocketErrorCode!=SocketError.ConnectionRefused) throw; Line(ssl,"WAIT"); return; }
                        if(!Track(target)) return;
                        try { Line(ssl,"OK"); Interlocked.Increment(ref tlsConnections); ssl.ReadTimeout=Timeout.Infinite; Pipe(target,ssl); }
                        finally { Forget(target); }
                    }
                } else Interlocked.Increment(ref rejected);
            } catch(Exception e) { Error(new IOException(stage+": "+e.Message,e)); }
            finally { c.Close(); if(ssl!=null) ssl.Dispose(); if(ownsUdp) Interlocked.Exchange(ref udpActive,0); Forget(c); }
        }
        private static byte[] Frame(Stream s, int max) {
            byte[] head = Exact(s,4); int n = head[0] | head[1]<<8 | head[2]<<16 | head[3]<<24;
            if(n<0 || n>max) throw new IOException("Invalid frame length"); return Exact(s,n);
        }
        private static byte[] Exact(Stream s, int n) {
            byte[] b=new byte[n]; int got=0; while(got<n) { int r=s.Read(b,got,n-got); if(r==0) throw new EndOfStreamException(); got+=r; } return b;
        }
        private static void SendFrame(Stream s, byte[] b, int count) {
            byte[] h={ (byte)count,(byte)(count>>8),(byte)(count>>16),(byte)(count>>24) }; s.Write(h,0,4); if(count>0) s.Write(b,0,count);
        }
        private void HostUdp(SslStream ssl) {
            // Preserve the bridge's UDP source port across Internet reconnects.
            // Its endpoint pinning then keeps queued actions on the same peer.
            UdpClient udp=hostUdp;
            {
                int done=0; Thread reverse=new Thread(delegate() {
                    int lastPulse=Environment.TickCount;
                    while(!stopped && Volatile.Read(ref done)==0) try { IPEndPoint from=null; byte[] b=udp.Receive(ref from); SendFrame(ssl,b,b.Length); Interlocked.Increment(ref udpPackets); }
                    catch(SocketException e) {
                        if(e.SocketErrorCode!=SocketError.TimedOut && e.SocketErrorCode!=SocketError.ConnectionReset && e.SocketErrorCode!=SocketError.ConnectionRefused) { try { ssl.Dispose(); } catch {} break; }
                        try { if(unchecked(Environment.TickCount-lastPulse)>=2000) { SendFrame(ssl,new byte[0],0); lastPulse=Environment.TickCount; } }
                        catch { try { ssl.Dispose(); } catch {} break; }
                    }
                    catch { try { ssl.Dispose(); } catch {} break; }
                }); reverse.IsBackground=true; reverse.Start();
                try { while(!stopped) { byte[] b=Frame(ssl,65507); if(b.Length==0) continue; udp.Send(b,b.Length); Interlocked.Increment(ref udpPackets); } }
                finally { Interlocked.Exchange(ref done,1); reverse.Join(2000); }
            }
        }
        private void ClientUdpSend() {
            int lastPulse=Environment.TickCount;
            while(!stopped) {
                IPEndPoint from=null; byte[] b=null;
                try { b=localUdp.Receive(ref from); if(!IPAddress.IsLoopback(from.Address)) continue; }
                catch(SocketException e) { if(e.SocketErrorCode!=SocketError.TimedOut) { Error(e); continue; } }
                catch(Exception e) { Error(e); if(stopped) return; continue; }
                try {
                    lock(writeGate) {
                        if(from!=null) gameEndpoint=from;
                        if(udpStream!=null && (b!=null || unchecked(Environment.TickCount-lastPulse)>=2000)) {
                            SendFrame(udpStream,b ?? new byte[0],b==null ? 0 : b.Length); lastPulse=Environment.TickCount;
                            if(b!=null) Interlocked.Increment(ref udpPackets);
                        }
                    }
                } catch(Exception e) { Error(e); lock(writeGate) { if(udpStream!=null) { try { udpStream.Dispose(); } catch {} } udpStream=null; } }
            }
        }
        private void ClientUdpConnect() {
            while(!stopped) {
                TcpClient c=null; SslStream ssl=null;
                try {
                    ssl=Connect("UDP",out c); ssl.ReadTimeout=15000; lock(writeGate) udpStream=ssl;
                    Interlocked.Exchange(ref udpActive,1); lock(gate) lastError="";
                    while(!stopped) { byte[] b=Frame(ssl,65507); if(b.Length==0) continue; IPEndPoint target; lock(writeGate) target=gameEndpoint; if(target!=null) localUdp.Send(b,b.Length,target); Interlocked.Increment(ref udpPackets); }
                } catch(Exception e) { Error(e); }
                finally { lock(writeGate) { udpStream=null; if(ssl!=null) ssl.Dispose(); } Interlocked.Exchange(ref udpActive,0); if(c!=null) Forget(c); }
                if(!stopped) { Interlocked.Increment(ref reconnects); for(int i=0;i<20 && !stopped;i++) Thread.Sleep(100); }
            }
        }
        private void ClientAccept() {
            while(!stopped) try { TcpClient c=listener.AcceptTcpClient(); if(Track(c)) Background(delegate {
                TcpClient remote=null; try {
                    Configure(c);
                    if(encryptTcp) { using(SslStream ssl=Connect("TCP",out remote)) { Interlocked.Increment(ref tlsConnections); Pipe(c,ssl); } }
                    else { using(Stream stream=ConnectPlain(out remote)) PipePlain(c,stream,remote.Client); }
                }
                catch(HostNotReadyException) {
                    // The save receiver retains its existing no-host wait/cancel policy.
                    try { BinaryWriter writer=new BinaryWriter(c.GetStream(),Encoding.UTF8); writer.Write("TF3MPWAIT"); writer.Flush(); } catch { }
                }
                catch(Exception e) { Error(e); } finally { if(remote!=null) Forget(remote); Forget(c); }
            }); } catch(Exception e) { Error(e); if(!stopped) Thread.Sleep(200); }
        }
        // A zero-length frame is a directional EOF. This preserves TCP half-close
        // semantics used when declining or cancelling a save, without losing replies.
        private void Pipe(TcpClient plain, SslStream ssl) {
            // The control socket is idle while the four data sockets transfer the
            // save. A handshake timeout here used to close it after seven seconds.
            plain.ReceiveTimeout=0;
            Stream data=plain.GetStream(); Exception reverseError=null;
            Thread reverse=new Thread(delegate() {
                try { byte[] b=new byte[65536]; int n; while((n=data.Read(b,0,b.Length))>0) { SendFrame(ssl,b,n); Interlocked.Add(ref tcpBytes,n); } SendFrame(ssl,b,0); }
                catch(Exception e) { reverseError=e; ssl.Dispose(); }
            }); reverse.IsBackground=true; reverse.Start();
            try {
                while(!stopped) { byte[] b=Frame(ssl,65536); if(b.Length==0) { plain.Client.Shutdown(SocketShutdown.Send); break; } data.Write(b,0,b.Length); Interlocked.Add(ref tcpBytes,b.Length); }
                // The remaining direction can carry the final save acknowledgement.
                if(!reverse.Join(15000)) throw new IOException("Tunnel half-close timed out");
                if(reverseError!=null) throw new IOException("Tunnel stream failed",reverseError);
            } finally { plain.Close(); ssl.Dispose(); reverse.Join(2000); }
        }
        private void PipePlain(TcpClient plain, Stream remote, Socket remoteSocket) {
            plain.ReceiveTimeout=0; remote.ReadTimeout=Timeout.Infinite; remote.WriteTimeout=15000;
            Stream data=plain.GetStream(); Exception reverseError=null;
            Thread reverse=new Thread(delegate() {
                try {
                    byte[] b=new byte[65536]; int n;
                    while((n=data.Read(b,0,b.Length))>0) { remote.Write(b,0,n); Interlocked.Add(ref tcpBytes,n); }
                    remoteSocket.Shutdown(SocketShutdown.Send);
                } catch(Exception e) { reverseError=e; try { remote.Dispose(); } catch {} }
            }); reverse.IsBackground=true; reverse.Start();
            try {
                byte[] b=new byte[65536]; int n;
                while(!stopped && (n=remote.Read(b,0,b.Length))>0) { data.Write(b,0,n); Interlocked.Add(ref tcpBytes,n); }
                plain.Client.Shutdown(SocketShutdown.Send);
                if(!reverse.Join(15000)) throw new IOException("Tunnel half-close timed out");
                if(reverseError!=null) throw new IOException("Tunnel stream failed",reverseError);
            } finally { plain.Close(); remote.Dispose(); reverse.Join(2000); }
        }
        public void Dispose() {
            if(stopped) return; stopped=true;
            if(listener!=null) listener.Stop(); if(localUdp!=null) localUdp.Close(); if(hostUdp!=null) hostUdp.Close();
            lock(gate) { foreach(TcpClient c in sockets) c.Close(); sockets.Clear(); }
            if(certificate!=null) certificate.Dispose();
        }
    }
}
