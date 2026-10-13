using System;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography.X509Certificates;
using System.Text;

// A real authenticated LOG/1 peer, independent of the production collector.
public sealed class DiagnosticLogFixture : IDisposable {
    public static void ExerciseRetention(string path,byte[] bytes,int repeats) {
        Type tunnel=null;
        foreach(System.Reflection.Assembly assembly in AppDomain.CurrentDomain.GetAssemblies()) {
            tunnel=assembly.GetType("TF3MP.Internet.Tunnel"); if(tunnel!=null) break;
        }
        System.Reflection.MethodInfo append=tunnel.GetMethod("DiagnosticAppend",System.Reflection.BindingFlags.Static|System.Reflection.BindingFlags.NonPublic);
        for(int i=0;i<repeats;i++) append.Invoke(null,new object[]{path,bytes,0,bytes.Length});
    }
    private readonly TcpClient client;
    private readonly SslStream stream;
    public DiagnosticLogFixture(int port,string pin,string key,string session) {
        client=new TcpClient("127.0.0.1",port); client.NoDelay=true; client.ReceiveTimeout=5000;
        stream=new SslStream(client.GetStream(),false,delegate(object sender,X509Certificate cert,X509Chain chain,SslPolicyErrors errors) {
            if(cert==null) return false;
            using(System.Security.Cryptography.SHA256 sha=System.Security.Cryptography.SHA256.Create())
                return BitConverter.ToString(sha.ComputeHash(cert.GetRawCertData())).Replace("-","").ToLowerInvariant()==pin;
        });
        try {
            stream.ReadTimeout=stream.WriteTimeout=5000; stream.AuthenticateAsClient("TF3MP invitation",null,SslProtocols.Tls12,false);
            Line("TF3MP-TLS/1"); Line(key); Line("LOG/1"); if(ReadLine()!="OK") throw new IOException("Diagnostic route refused");
            Line(session); if(ReadLine()!="READY") throw new IOException("Diagnostic session refused");
        } catch { Dispose(); throw; }
    }
    private void Line(string value) { byte[] bytes=Encoding.ASCII.GetBytes(value+"\n"); stream.Write(bytes,0,bytes.Length); }
    private string ReadLine() { string value=""; for(int i=0;i<160;i++) { int b=stream.ReadByte(); if(b<0) throw new EndOfStreamException(); if(b==10) return value; value+=(char)b; } throw new IOException(); }
    private void Frame(byte[] bytes) { byte[] header=BitConverter.GetBytes(bytes.Length); stream.Write(header,0,4); stream.Write(bytes,0,bytes.Length); }
    private byte[] Frame() { byte[] head=Exact(4); int count=BitConverter.ToInt32(head,0); if(count<0 || count>100) throw new IOException(); return Exact(count); }
    private byte[] Exact(int count) { byte[] bytes=new byte[count]; int at=0,n; while(at<count && (n=stream.Read(bytes,at,count-at))>0) at+=n; if(at<count) throw new EndOfStreamException(); return bytes; }
    public void Send(byte kind,string source,long offset,byte[] bytes) {
        byte[] frame=new byte[26+bytes.Length]; frame[0]=1; frame[1]=kind;
        for(int i=0;i<16;i++) frame[2+i]=Convert.ToByte(source.Substring(i*2,2),16);
        Buffer.BlockCopy(BitConverter.GetBytes(offset),0,frame,18,8); Buffer.BlockCopy(bytes,0,frame,26,bytes.Length); Frame(frame);
    }
    public long Ack() { byte[] bytes=Frame(); if(bytes.Length!=10 || bytes[0]!=2) throw new IOException(); return BitConverter.ToInt64(bytes,2); }
    public long Append(byte kind,string source,long offset,byte[] bytes) { Send(kind,source,offset,bytes); return Ack(); }
    public bool Malformed(int scenario) {
        if(scenario==0) { byte[] tooLong=BitConverter.GetBytes(32769); stream.Write(tooLong,0,4); }
        else if(scenario==1) Frame(new byte[]{99});
        else if(scenario==2) Send(7,new string('d',32),0,new byte[]{42});
        else if(scenario==3) Send(1,new string('d',32),-1,new byte[]{42});
        else if(scenario==4) Send(1,new string('d',32),Int64.MaxValue,new byte[]{42});
        try { return stream.ReadByte()<0; } catch(IOException) { return true; }
    }
    public void Dispose() { try { if(stream!=null) stream.Dispose(); } finally { if(client!=null) client.Close(); } }
}
