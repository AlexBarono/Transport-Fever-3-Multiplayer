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
using System.Text.RegularExpressions;
using System.Runtime.InteropServices;
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

        // Diagnostics have their own authenticated TLS connection and failure state.
        // Neither a slow disk nor a missing log can hold up game/save traffic.
        private const int DiagnosticFrameLimit=32768, DiagnosticLineLimit=512*1024;
        private const int DiagnosticTailLimit=2*1024*1024, DiagnosticFileLimit=8*1024*1024;
        private readonly object diagnosticGate=new object();
        private readonly AutoResetEvent diagnosticWake=new AutoResetEvent(false);
        private readonly Dictionary<byte,string> diagnosticPaths=new Dictionary<byte,string>();
        private readonly Dictionary<string,DiagnosticSession> diagnosticSessions=new Dictionary<string,DiagnosticSession>();
        private string diagnosticRoot="";
        private volatile string diagnosticDirectory="", diagnosticError="";
        private readonly string diagnosticSessionId=NewKey().Substring(0,32);
        private int diagnosticActive, diagnosticCollectorStarted;
        private Thread diagnosticThread;
        private long diagnosticBytesSent, diagnosticBytesReceived;
        public string DiagnosticDirectory { get { return diagnosticDirectory; } }
        public string DiagnosticLastError { get { return diagnosticError; } }
        public long DiagnosticBytesSent { get { return Interlocked.Read(ref diagnosticBytesSent); } }
        public long DiagnosticBytesReceived { get { return Interlocked.Read(ref diagnosticBytesReceived); } }
        public bool DiagnosticConnected { get { return Volatile.Read(ref diagnosticActive)!=0; } }
        private static readonly string[] DiagnosticKinds={"", "stdout", "bridge", "launcher", "status", "internet", "transfer"};
        private sealed class DiagnosticSink {
            internal string Id, Path; internal long Offset;
        }
        private sealed class DiagnosticSession {
            internal string Directory; internal readonly Dictionary<byte,DiagnosticSink> Sources=new Dictionary<byte,DiagnosticSink>();
        }
        private sealed class DiagnosticSource {
            internal byte Kind; internal string Path, Id, Identity="", Prefix="", Boundary="", SnapshotHash="";
            internal long RawOffset, AckedOffset;
            internal bool Initialized, SkipLine, AtEof;
            internal string NextGap="";
            internal DateTime PollAfter=DateTime.MinValue;
            internal DateTime LastGrowth=DateTime.UtcNow;
            internal DateTime UnavailableSince=DateTime.MinValue;
            internal readonly Queue<string> NextPaths=new Queue<string>();
            internal MemoryStream Partial=new MemoryStream();
            internal byte[] Input, Output, DeferredOutput; internal int InputAt, OutputAt;
            internal DiagnosticSource(byte kind,string path) { Kind=kind; Path=path; Id=NewKey().Substring(0,32); }
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct DiagnosticFileInfo {
            internal uint Attributes;
            internal System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
            internal uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }
        [DllImport("kernel32.dll",SetLastError=true)]
        private static extern bool GetFileInformationByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle file, out DiagnosticFileInfo information);
        private static byte DiagnosticKind(string value) {
            for(byte i=1;i<DiagnosticKinds.Length;i++) if(String.Equals(value,DiagnosticKinds[i],StringComparison.Ordinal)) return i;
            throw new ArgumentException("Unsupported diagnostic source kind");
        }
        public void EnableDiagnosticReceiver(string root) {
            if(host!=null || stopped) throw new InvalidOperationException("Diagnostic receiver requires a running host");
            string resolved=System.IO.Path.GetFullPath(root);
            lock(diagnosticGate) {
                if(diagnosticRoot.Length!=0 && !String.Equals(diagnosticRoot,resolved,StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Diagnostic receiver is already configured");
                diagnosticRoot=resolved; if(diagnosticDirectory.Length==0) diagnosticDirectory=resolved;
            }
        }
        // These are trusted local paths. Only the logical kind and a random stream
        // identifier cross the network; the peer never supplies a filesystem path.
        public void SetDiagnosticSources(string[] kinds,string[] paths) {
            if(host==null || stopped) throw new InvalidOperationException("Diagnostic sources require a running client");
            if(kinds==null || paths==null || kinds.Length!=paths.Length || kinds.Length>6) throw new ArgumentException("Invalid diagnostic source list");
            Dictionary<byte,string> replacement=new Dictionary<byte,string>();
            for(int i=0;i<kinds.Length;i++) {
                byte kind=DiagnosticKind(kinds[i]);
                if(replacement.ContainsKey(kind)) throw new ArgumentException("Duplicate diagnostic source kind");
                if(String.IsNullOrWhiteSpace(paths[i])) throw new ArgumentException("Missing diagnostic source path");
                replacement.Add(kind,System.IO.Path.GetFullPath(paths[i]));
            }
            lock(diagnosticGate) { diagnosticPaths.Clear(); foreach(KeyValuePair<byte,string> p in replacement) diagnosticPaths.Add(p.Key,p.Value); }
            lock(gate) if(!stopped && Interlocked.CompareExchange(ref diagnosticCollectorStarted,1,0)==0) {
                diagnosticThread=new Thread(ClientDiagnostics); diagnosticThread.IsBackground=true; diagnosticThread.Start();
            }
            lock(gate) if(!stopped) diagnosticWake.Set();
        }
        private void DiagnosticError(Exception error) {
            if(stopped) return;
            // Exception messages can include local paths or an invitation. Retain
            // bounded exception/socket types only, never their uncontrolled text.
            string value=error.GetType().Name; Exception current=error;
            for(int i=0;i<4 && current!=null;i++,current=current.InnerException) {
                SocketException socket=current as SocketException;
                if(socket!=null) { value+=" / "+socket.SocketErrorCode.ToString(); break; }
            }
            diagnosticError=value;
        }
        private static bool DiagnosticId(string value) {
            if(value.Length!=32) return false;
            foreach(char c in value) if(!((c>='0' && c<='9') || (c>='a' && c<='f'))) return false;
            return true;
        }
        private static byte[] DiagnosticIdBytes(string id) {
            byte[] bytes=new byte[16]; for(int i=0;i<16;i++) bytes[i]=Convert.ToByte(id.Substring(i*2,2),16); return bytes;
        }
        private static string DiagnosticIdString(byte[] frame,int at) {
            return BitConverter.ToString(frame,at,16).Replace("-","").ToLowerInvariant();
        }
        private void HostDiagnostics(SslStream ssl) {
            ssl.ReadTimeout=15000;
            string sessionId=ReadLine(ssl); if(!DiagnosticId(sessionId)) throw new IOException("Invalid diagnostic session identifier");
            DiagnosticSession session;
            {
                if(!diagnosticSessions.TryGetValue(sessionId,out session)) {
                    if(diagnosticSessions.Count>=4) {
                        // Only one diagnostic connection is admitted at a time.
                        // Drop the oldest resume state, retaining its received files.
                        string oldest=null; foreach(string old in diagnosticSessions.Keys) { oldest=old; break; }
                        if(oldest!=null) diagnosticSessions.Remove(oldest);
                    }
                    // The host assigns this folder. The remote identifier is only
                    // a dictionary key and never becomes part of any local path.
                    session=new DiagnosticSession(); session.Directory=System.IO.Path.Combine(diagnosticRoot,"client-"+Guid.NewGuid().ToString("N"));
                    System.IO.Directory.CreateDirectory(session.Directory);
                    File.WriteAllText(System.IO.Path.Combine(session.Directory,"session.txt"),"TF3MP remote diagnostics LOG/1\r\nStarted UTC: "+DateTime.UtcNow.ToString("o")+"\r\n",new UTF8Encoding(false));
                    diagnosticSessions.Add(sessionId,session);
                }
                diagnosticDirectory=session.Directory; diagnosticError="";
            }
            Line(ssl,"READY");
            while(!stopped) {
                byte[] frame=Frame(ssl,DiagnosticFrameLimit);
                if(frame.Length==1 && frame[0]==0) { SendFrame(ssl,frame,1); continue; }
                if(frame.Length<=26 || frame[0]!=1 || frame[1]<1 || frame[1]>=DiagnosticKinds.Length) throw new IOException("Invalid diagnostic frame");
                byte kind=frame[1]; string sourceId=DiagnosticIdString(frame,2); long offset=BitConverter.ToInt64(frame,18); int count=frame.Length-26;
                if(offset<0 || offset>Int64.MaxValue-count) throw new IOException("Invalid diagnostic offset");
                long acknowledged;
                {
                    DiagnosticSink sink;
                    if(!session.Sources.TryGetValue(kind,out sink)) {
                        if(offset!=0) throw new IOException("Unknown diagnostic stream offset");
                        sink=new DiagnosticSink(); sink.Id=sourceId; sink.Path=System.IO.Path.Combine(session.Directory,DiagnosticKinds[kind]+".log"); session.Sources.Add(kind,sink);
                    } else if(sink.Id!=sourceId) {
                        if(offset!=0) throw new IOException("Changed diagnostic stream offset");
                        sink.Id=sourceId; sink.Offset=0;
                        byte[] marker=Encoding.UTF8.GetBytes("\n[TF3MP diagnostics: source replaced or truncated]\n");
                        DiagnosticAppend(sink.Path,marker,0,marker.Length);
                    }
                    if(offset==sink.Offset) {
                        DiagnosticAppend(sink.Path,frame,26,count); sink.Offset+=count;
                        Interlocked.Add(ref diagnosticBytesReceived,count);
                    } else if(offset>sink.Offset || offset+count>sink.Offset) throw new IOException("Diagnostic offset gap");
                    // A full repeated frame means its ACK was lost. Never append
                    // it twice, including after reconnect or file rotation.
                    acknowledged=sink.Offset; diagnosticError="";
                }
                byte[] answer=new byte[10]; answer[0]=2; answer[1]=kind; Buffer.BlockCopy(BitConverter.GetBytes(acknowledged),0,answer,2,8); SendFrame(ssl,answer,answer.Length);
            }
        }
        private static void DiagnosticAppend(string path,byte[] bytes,int at,int count) {
            long length=File.Exists(path) ? new FileInfo(path).Length : 0;
            if(length+count>DiagnosticFileLimit) {
                string previous=path+".previous"; if(File.Exists(previous)) File.Delete(previous); File.Move(path,previous);
                byte[] marker=Encoding.UTF8.GetBytes("[TF3MP diagnostics: older bytes rotated; preceding part is in .previous]\n");
                File.WriteAllBytes(path,marker);
            }
            using(FileStream file=new FileStream(path,FileMode.Append,FileAccess.Write,FileShare.ReadWrite)) { file.Write(bytes,at,count); file.Flush(); }
        }
        private string RedactDiagnostic(string value) {
            value=Regex.Replace(value,@"tf3mp-internet://[^\s\""'<>]+","[invitation redacted]",RegexOptions.IgnoreCase);
            if(!String.IsNullOrEmpty(secret)) value=Regex.Replace(value,Regex.Escape(secret),"[key redacted]",RegexOptions.IgnoreCase);
            if(!String.IsNullOrEmpty(pin)) value=Regex.Replace(value,Regex.Escape(pin),"[pin redacted]",RegexOptions.IgnoreCase);
            return value;
        }
        private static string FileIdentity(FileStream file) {
            DiagnosticFileInfo info;
            if(GetFileInformationByHandle(file.SafeFileHandle,out info)) return info.Volume.ToString("x8")+info.IndexHigh.ToString("x8")+info.IndexLow.ToString("x8");
            throw new IOException("Diagnostic file identity unavailable");
        }
        private static string FilePiece(FileStream file,long at,int count) {
            file.Position=at; byte[] bytes=new byte[count]; int got=0,n;
            while(got<count && (n=file.Read(bytes,got,count-got))>0) got+=n;
            if(got!=count) throw new IOException("Diagnostic source changed during read"); return Hash(bytes);
        }
        private void ResetDiagnosticSource(DiagnosticSource source,long length,string identity,string prefix) {
            bool replaced=source.Initialized;
            source.Id=NewKey().Substring(0,32); source.AckedOffset=0; source.Initialized=true;
            source.Identity=identity; source.Prefix=prefix; source.Boundary=""; source.RawOffset=Math.Max(0,length-DiagnosticTailLimit);
            source.LastGrowth=DateTime.UtcNow; source.AtEof=false;
            source.UnavailableSince=DateTime.MinValue;
            source.Input=null; source.DeferredOutput=null; source.InputAt=0; source.Partial.SetLength(0); source.SkipLine=source.RawOffset>0;
            string marker=replaced ? "[TF3MP diagnostics: source replaced/truncated; new tail follows]\n" : "[TF3MP diagnostics: source tail begins]\n";
            if(source.RawOffset>0) marker+="[TF3MP diagnostics: "+source.RawOffset+" earlier source bytes omitted; partial first line skipped]\n";
            source.Output=Encoding.UTF8.GetBytes(marker); source.OutputAt=0;
        }
        private bool ReadDiagnosticSnapshot(DiagnosticSource source) {
            if(DateTime.UtcNow<source.PollAfter) return false; source.PollAfter=DateTime.UtcNow.AddSeconds(2);
            try {
                using(FileStream file=new FileStream(source.Path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)) {
                    if(file.Length>DiagnosticFrameLimit) {
                        source.UnavailableSince=DateTime.MinValue;
                        if(source.SnapshotHash=="oversized") return false; source.SnapshotHash="oversized";
                        source.Output=Encoding.UTF8.GetBytes("[TF3MP diagnostics: status snapshot omitted (>32 KiB)]\n"); source.OutputAt=0; source.AtEof=true; source.LastGrowth=DateTime.UtcNow; return true;
                    }
                    byte[] bytes=new byte[(int)file.Length]; int got=0,n;
                    while(got<bytes.Length && (n=file.Read(bytes,got,bytes.Length-got))>0) got+=n;
                    source.UnavailableSince=DateTime.MinValue;
                    if(got!=bytes.Length) return false;
                    string hash=Hash(bytes); source.AtEof=true; if(hash==source.SnapshotHash) return false; source.SnapshotHash=hash; source.LastGrowth=DateTime.UtcNow;
                    string value="\n[TF3MP status UTC "+DateTime.UtcNow.ToString("o")+"]\n"+Encoding.UTF8.GetString(bytes);
                    source.Output=Encoding.UTF8.GetBytes(RedactDiagnostic(value)+"\n"); source.OutputAt=0; return true;
                }
            } catch(FileNotFoundException) { source.AtEof=true; return false; } catch(DirectoryNotFoundException) { source.AtEof=true; return false; }
        }
        private bool ReadDiagnosticSource(DiagnosticSource source) {
            if(source.Output!=null) return true;
            if(source.DeferredOutput!=null) { source.Output=source.DeferredOutput; source.DeferredOutput=null; source.OutputAt=0; return true; }
            if(source.Kind==4) return ReadDiagnosticSnapshot(source);
            // Complete a bounded line before redaction. This prevents a split
            // invitation/key from leaking at a file-read or upload-frame boundary.
            if(source.Input!=null) {
                MemoryStream batch=new MemoryStream();
                while(source.InputAt<source.Input.Length) {
                    byte b=source.Input[source.InputAt++];
                    if(source.SkipLine) { if(b==10) source.SkipLine=false; continue; }
                    if(source.Partial.Length>=DiagnosticLineLimit) {
                        source.Partial.SetLength(0); source.SkipLine=b!=10;
                        if(BatchDiagnosticOutput(source,batch,Encoding.UTF8.GetBytes("[TF3MP diagnostics: oversized line omitted (>512 KiB)]\n"))) return true;
                        continue;
                    }
                    source.Partial.WriteByte(b);
                    if(b==10) {
                        byte[] line=Encoding.UTF8.GetBytes(RedactDiagnostic(Encoding.UTF8.GetString(source.Partial.ToArray())));
                        source.Partial.SetLength(0); if(BatchDiagnosticOutput(source,batch,line)) return true;
                    }
                }
                source.Input=null; source.InputAt=0;
                if(batch.Length!=0) { source.Output=batch.ToArray(); source.OutputAt=0; return true; }
            }
            if(DateTime.UtcNow<source.PollAfter) return false;
            source.PollAfter=DateTime.UtcNow.AddMilliseconds(250);
            try {
                using(FileStream file=new FileStream(source.Path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)) {
                    long length=file.Length; string identity=FileIdentity(file);
                    // Prefixes shorter than 64 bytes naturally grow on append. A
                    // boundary check detects rewriting even with a stable prefix.
                    int prefixLength=(int)Math.Min(64,length);
                    string prefix=FilePiece(file,0,prefixLength);
                    bool changed=source.Initialized && (identity!=source.Identity || length<source.RawOffset);
                    if(source.Initialized && !changed && source.RawOffset>0 && source.Boundary.Length!=0)
                        changed=FilePiece(file,Math.Max(0,source.RawOffset-64),(int)Math.Min(64,source.RawOffset))!=source.Boundary;
                    if(!source.Initialized || changed) { ResetDiagnosticSource(source,length,identity,prefix); return true; }
                    if(source.RawOffset>=length) { source.AtEof=true; source.UnavailableSince=DateTime.MinValue; return false; }
                    file.Position=source.RawOffset; byte[] bytes=new byte[(int)Math.Min(DiagnosticFrameLimit,length-source.RawOffset)]; int got=file.Read(bytes,0,bytes.Length);
                    if(got==0) return false; if(got!=bytes.Length) Array.Resize(ref bytes,got);
                    source.RawOffset+=got; source.Input=bytes; source.AtEof=false; source.LastGrowth=DateTime.UtcNow;
                    source.Boundary=FilePiece(file,Math.Max(0,source.RawOffset-64),(int)Math.Min(64,source.RawOffset));
                    source.UnavailableSince=DateTime.MinValue;
                }
            } catch(FileNotFoundException) { source.AtEof=true; return false; } catch(DirectoryNotFoundException) { source.AtEof=true; return false; }
            // Process this read on the next round, giving the other sources turns.
            return false;
        }
        private static bool BatchDiagnosticOutput(DiagnosticSource source,MemoryStream batch,byte[] line) {
            if(batch.Length==0 && line.Length>=DiagnosticFrameLimit-26) { source.Output=line; source.OutputAt=0; return true; }
            if(batch.Length+line.Length>DiagnosticFrameLimit-26) {
                source.Output=batch.ToArray(); source.OutputAt=0; source.DeferredOutput=line; return true;
            }
            batch.Write(line,0,line.Length); return false;
        }
        private void DiagnosticWait(int milliseconds) { if(!stopped) diagnosticWake.WaitOne(milliseconds); }
        private void ClientDiagnostics() {
            Dictionary<byte,DiagnosticSource> sources=new Dictionary<byte,DiagnosticSource>(); int backoff=2000;
            while(!stopped) {
                TcpClient c=null; SslStream ssl=null;
                try {
                    bool configured; lock(diagnosticGate) configured=diagnosticPaths.Count!=0;
                    if(!configured) { DiagnosticWait(1000); continue; }
                    ssl=Connect("LOG/1",out c); ssl.ReadTimeout=15000; Line(ssl,diagnosticSessionId);
                    if(ReadLine(ssl)!="READY") throw new IOException("Diagnostic receiver not ready");
                    Interlocked.Exchange(ref diagnosticActive,1); lock(diagnosticGate) diagnosticError=""; backoff=2000;
                    DateTime pulse=DateTime.UtcNow, nextSend=DateTime.UtcNow;
                    while(!stopped) {
                        Dictionary<byte,string> paths;
                        lock(diagnosticGate) paths=new Dictionary<byte,string>(diagnosticPaths);
                        foreach(KeyValuePair<byte,string> p in paths) {
                            DiagnosticSource existing;
                            if(!sources.TryGetValue(p.Key,out existing)) sources[p.Key]=new DiagnosticSource(p.Key,p.Value);
                            else if(!String.Equals(existing.Path,p.Value,StringComparison.OrdinalIgnoreCase) && !existing.NextPaths.Contains(p.Value)) {
                                if(existing.NextPaths.Count>=2) { existing.NextPaths.Dequeue(); existing.NextGap="source generation backlog exceeded; intermediate file omitted"; }
                                existing.NextPaths.Enqueue(p.Value);
                            }
                        }
                        bool sent=false;
                        foreach(KeyValuePair<byte,DiagnosticSource> p in new List<KeyValuePair<byte,DiagnosticSource>>(sources)) {
                            if(!paths.ContainsKey(p.Key)) continue;
                            DiagnosticSource source=p.Value;
                            if(source.NextPaths.Count!=0 && source.Output==null && source.DeferredOutput==null && source.Input==null && source.AtEof && (DateTime.UtcNow-source.LastGrowth).TotalSeconds>=2) {
                                // Verify EOF again now: a final failure line may
                                // have appeared since the previous polling round.
                                if(source.UnavailableSince!=DateTime.MinValue && (DateTime.UtcNow-source.UnavailableSince).TotalSeconds>=10)
                                    source.NextGap="unreadable source retired after 10 s; some source bytes omitted";
                                else {
                                    if(source.UnavailableSince!=DateTime.MinValue && DateTime.UtcNow<source.PollAfter) continue;
                                    source.PollAfter=DateTime.MinValue;
                                    try { ReadDiagnosticSource(source); source.UnavailableSince=DateTime.MinValue; }
                                    catch(Exception e) { DiagnosticError(e); if(source.UnavailableSince==DateTime.MinValue) source.UnavailableSince=DateTime.UtcNow; source.AtEof=true; source.PollAfter=DateTime.UtcNow.AddSeconds(2); continue; }
                                }
                            }
                            if(source.NextPaths.Count!=0 && source.Output==null && source.DeferredOutput==null && source.Input==null && source.AtEof && (DateTime.UtcNow-source.LastGrowth).TotalSeconds>=2) {
                                if(source.Partial.Length!=0) {
                                    source.Output=Encoding.UTF8.GetBytes(RedactDiagnostic(Encoding.UTF8.GetString(source.Partial.ToArray()))+"\n[TF3MP diagnostics: final unterminated line ended with source]\n"); source.Partial.SetLength(0); source.OutputAt=0;
                                } else {
                                    DiagnosticSource next=new DiagnosticSource(source.Kind,source.NextPaths.Dequeue());
                                    foreach(string remaining in source.NextPaths) next.NextPaths.Enqueue(remaining);
                                    if(source.NextGap.Length!=0) next.Output=Encoding.UTF8.GetBytes("[TF3MP diagnostics: "+source.NextGap+"]\n");
                                    source.Partial.Dispose(); sources[p.Key]=next; source=next;
                                }
                            }
                            try { if(!ReadDiagnosticSource(source)) continue; }
                            catch(Exception e) { DiagnosticError(e); if(source.UnavailableSince==DateTime.MinValue) source.UnavailableSince=DateTime.UtcNow; source.AtEof=true; source.PollAfter=DateTime.UtcNow.AddSeconds(2); continue; }
                            while(!stopped && DateTime.UtcNow<nextSend) DiagnosticWait(Math.Min(100,Math.Max(1,(int)(nextSend-DateTime.UtcNow).TotalMilliseconds)));
                            if(stopped) break;
                            int count=Math.Min(DiagnosticFrameLimit-26,source.Output.Length-source.OutputAt);
                            byte[] frame=new byte[26+count]; frame[0]=1; frame[1]=source.Kind;
                            Buffer.BlockCopy(DiagnosticIdBytes(source.Id),0,frame,2,16); Buffer.BlockCopy(BitConverter.GetBytes(source.AckedOffset),0,frame,18,8);
                            Buffer.BlockCopy(source.Output,source.OutputAt,frame,26,count);
                            SendFrame(ssl,frame,frame.Length);
                            byte[] answer=Frame(ssl,10);
                            if(answer.Length!=10 || answer[0]!=2 || answer[1]!=source.Kind || BitConverter.ToInt64(answer,2)!=source.AckedOffset+count)
                                throw new IOException("Invalid diagnostic acknowledgement");
                            source.AckedOffset+=count; source.OutputAt+=count; Interlocked.Add(ref diagnosticBytesSent,count);
                            if(source.OutputAt==source.Output.Length) { source.Output=null; source.OutputAt=0; }
                            nextSend=DateTime.UtcNow.AddSeconds((double)count/(64*1024)); pulse=DateTime.UtcNow; sent=true;
                            lock(diagnosticGate) diagnosticError="";
                        }
                        if(!sent && (DateTime.UtcNow-pulse).TotalSeconds>=2) {
                            SendFrame(ssl,new byte[]{0},1); byte[] answer=Frame(ssl,1);
                            if(answer.Length!=1 || answer[0]!=0) throw new IOException("Invalid diagnostic heartbeat"); pulse=DateTime.UtcNow;
                        }
                        DiagnosticWait(50);
                    }
                } catch(Exception e) { DiagnosticError(e); }
                finally { Interlocked.Exchange(ref diagnosticActive,0); if(ssl!=null) ssl.Dispose(); if(c!=null) Forget(c); }
                if(!stopped) { DiagnosticWait(backoff); backoff=Math.Min(30000,backoff*2); }
            }
            foreach(DiagnosticSource source in sources.Values) source.Partial.Dispose();
        }

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
            SslStream ssl = null; bool ownsUdp = false, ownsDiagnostics=false;
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
                if(route=="LOG/1") {
                    bool enabled; lock(diagnosticGate) enabled=diagnosticRoot.Length!=0;
                    if(!enabled || Interlocked.CompareExchange(ref diagnosticActive,1,0)!=0) { Line(ssl,"WAIT"); return; }
                    ownsDiagnostics=true; Line(ssl,"OK"); HostDiagnostics(ssl); return;
                }
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
            } catch(Exception e) { if(stage=="LOG/1") DiagnosticError(e); else Error(new IOException(stage+": "+e.Message,e)); }
            finally { c.Close(); if(ssl!=null) ssl.Dispose(); if(ownsUdp) Interlocked.Exchange(ref udpActive,0); if(ownsDiagnostics) Interlocked.Exchange(ref diagnosticActive,0); Forget(c); }
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
            diagnosticWake.Set();
            if(listener!=null) listener.Stop(); if(localUdp!=null) localUdp.Close(); if(hostUdp!=null) hostUdp.Close();
            lock(gate) { foreach(TcpClient c in sockets) c.Close(); sockets.Clear(); }
            if(certificate!=null) certificate.Dispose();
            if(diagnosticThread==null || diagnosticThread==Thread.CurrentThread || diagnosticThread.Join(2000)) diagnosticWake.Close();
        }
    }
}
