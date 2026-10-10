using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Xml;
public sealed class RouterFixture : IDisposable {
    private TcpListener listener=new TcpListener(IPAddress.Loopback,0);
    private volatile bool stopped;
    public volatile bool Deny, FailRenew;
    public int Adds, Updates, Deletes;
    public string AddedFields="", DeletedId="";
    public Uri Url { get; private set; }
    public RouterFixture() {
        listener.Start(); Url=new Uri("http://127.0.0.1:"+((IPEndPoint)listener.LocalEndpoint).Port+"/control");
        Thread t=new Thread(Run); t.IsBackground=true; t.Start();
    }
    private void Run() {
        while(!stopped) {
            TcpClient client;
            try { client=listener.AcceptTcpClient(); } catch { return; }
            using(client) try {
                client.ReceiveTimeout=3000; Stream stream=client.GetStream(); StringBuilder header=new StringBuilder();
                while(header.Length<8192 && !header.ToString().EndsWith("\r\n\r\n")) { int ch=stream.ReadByte(); if(ch<0) break; header.Append((char)ch); }
                int length=0;
                foreach(string line in header.ToString().Split('\n')) if(line.StartsWith("Content-Length:",StringComparison.OrdinalIgnoreCase)) length=int.Parse(line.Substring(15).Trim());
                byte[] bytes=new byte[length]; for(int n=0;n<length;) { int got=stream.Read(bytes,n,length-n); if(got==0) break; n+=got; }
                XmlDocument xml=new XmlDocument(); xml.LoadXml(Encoding.UTF8.GetString(bytes));
                XmlNode action=xml.SelectSingleNode("//*[local-name()='Body']/*"); string value="", code="";
                switch(action.LocalName) {
                    case "GetFirewallStatus": value="<FirewallEnabled>1</FirewallEnabled><InboundPinholeAllowed>"+(Deny?"0":"1")+"</InboundPinholeAllowed>"; break;
                    case "AddPinhole": Adds++; AddedFields=action.InnerXml; value="<UniqueID>42</UniqueID>"; break;
                    case "UpdatePinhole": Updates++; if(FailRenew) code="704"; break;
                    case "DeletePinhole": Deletes++; DeletedId=action.InnerText; break;
                    default: code="401"; break;
                }
                string body=code.Length==0 ? "<u:"+action.LocalName+"Response xmlns:u=\"urn:schemas-upnp-org:service:WANIPv6FirewallControl:1\">"+value+"</u:"+action.LocalName+"Response>" : "<s:Fault><detail><errorCode>"+code+"</errorCode></detail></s:Fault>";
                byte[] response=Encoding.UTF8.GetBytes("<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body>"+body+"</s:Body></s:Envelope>");
                byte[] head=Encoding.ASCII.GetBytes("HTTP/1.1 "+(code.Length==0?"200 OK":"500 Error")+"\r\nContent-Type: text/xml\r\nContent-Length: "+response.Length+"\r\nConnection: close\r\n\r\n");
                stream.Write(head,0,head.Length); stream.Write(response,0,response.Length);
            } catch { }
        }
    }
    public void Dispose() { stopped=true; listener.Stop(); }
}
