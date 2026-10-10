// UPnP IPv6 firewall control. A lease only opens the selected TLS/TCP port.
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Xml;

namespace TF3MP.Internet {
    public sealed class RouterException : IOException {
        public string Code { get; private set; }
        public RouterException(string code) : base("Router: " + code) { Code = code; }
    }
    public sealed class RouterLease : IDisposable {
        public const string Service = "urn:schemas-upnp-org:service:WANIPv6FirewallControl:1";
        private readonly object gate = new object(), requestGate = new object();
        private readonly Uri control;
        private readonly int seconds;
        private Timer renewal;
        private bool disposed;
        private int id = -1;
        private string error = "";
        private DateTime expires;
        public string LastError { get { lock(gate) return error; } }
        public bool Active { get { lock(gate) return !disposed && (id < 0 || DateTime.UtcNow < expires); } }
        public bool FirewallDisabled { get; private set; }
        public int Renewals { get; private set; }
        private RouterLease(Uri uri, int leaseSeconds) { control=uri; seconds=leaseSeconds; }

        // Only accept discovery/control URLs on the selected LAN's default gateway.
        // Never follow an SSDP response or redirect to an arbitrary LAN/Internet host.
        public static Uri ValidateUrl(string value, string gateway) {
            Uri uri; IPAddress ip;
            if (!Uri.TryCreate(value,UriKind.Absolute,out uri) || uri.Scheme != "http" ||
                uri.UserInfo.Length != 0 || !IPAddress.TryParse(uri.Host,out ip) ||
                !ip.Equals(IPAddress.Parse(gateway))) throw new RouterException("untrusted_endpoint");
            return uri;
        }
        private static XmlDocument Xml(Stream stream) {
            XmlReaderSettings settings=new XmlReaderSettings(); settings.DtdProcessing=DtdProcessing.Prohibit;
            settings.XmlResolver=null; settings.MaxCharactersInDocument=262144;
            XmlDocument xml=new XmlDocument(); xml.XmlResolver=null;
            using(XmlReader reader=XmlReader.Create(stream,settings)) xml.Load(reader);
            return xml;
        }
        private static HttpWebRequest Request(Uri uri) {
            HttpWebRequest req=(HttpWebRequest)WebRequest.Create(uri); req.Proxy=null;
            req.AllowAutoRedirect=false; req.Timeout=3000; req.ReadWriteTimeout=3000; req.KeepAlive=false;
            return req;
        }
        public static Uri Discover(string localAddress, string gateway) {
            using(UdpClient udp=new UdpClient(new IPEndPoint(IPAddress.Parse(localAddress),0))) {
                udp.Client.ReceiveTimeout=250;
                byte[] search=Encoding.ASCII.GetBytes("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n\r\n");
                udp.Send(search,search.Length,new IPEndPoint(IPAddress.Parse("239.255.255.250"),1900));
                DateTime deadline=DateTime.UtcNow.AddSeconds(3);
                while(DateTime.UtcNow < deadline) {
                    IPEndPoint from=new IPEndPoint(IPAddress.Any,0); byte[] reply;
                    try { reply=udp.Receive(ref from); } catch(SocketException e) { if(e.SocketErrorCode==SocketError.TimedOut) continue; throw; }
                    if(!from.Address.Equals(IPAddress.Parse(gateway))) continue;
                    foreach(string line in Encoding.ASCII.GetString(reply).Split('\n')) {
                        if(!line.StartsWith("location:",StringComparison.OrdinalIgnoreCase)) continue;
                        Uri location=ValidateUrl(line.Substring(9).Trim(),gateway);
                        using(WebResponse response=Request(location).GetResponse()) {
                            XmlDocument xml=Xml(response.GetResponseStream());
                            foreach(XmlNode service in xml.SelectNodes("//*[local-name()='service']")) {
                                XmlNode type=service.SelectSingleNode("*[local-name()='serviceType']");
                                XmlNode path=service.SelectSingleNode("*[local-name()='controlURL']");
                                if(type!=null && path!=null && type.InnerText==Service)
                                    return ValidateUrl(new Uri(location,path.InnerText).AbsoluteUri,gateway);
                            }
                        }
                        throw new RouterException("ipv6_service_missing");
                    }
                }
            }
            throw new RouterException("discovery_timeout");
        }
        private static XmlDocument Soap(Uri uri, string action, string fields) {
            byte[] bytes=Encoding.UTF8.GetBytes("<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body><u:"+action+" xmlns:u=\""+Service+"\">"+fields+"</u:"+action+"></s:Body></s:Envelope>");
            HttpWebRequest req=Request(uri); req.Method="POST"; req.ContentType="text/xml; charset=utf-8";
            req.Headers["SOAPAction"]="\""+Service+"#"+action+"\""; req.ContentLength=bytes.Length;
            using(Stream stream=req.GetRequestStream()) stream.Write(bytes,0,bytes.Length);
            XmlDocument xml;
            try { using(WebResponse response=req.GetResponse()) xml=Xml(response.GetResponseStream()); }
            catch(WebException e) {
                if(e.Response==null) throw new RouterException("request_timeout_or_unreachable");
                using(WebResponse response=e.Response) xml=Xml(response.GetResponseStream());
            }
            XmlNode fault=xml.SelectSingleNode("//*[local-name()='errorCode']");
            if(fault!=null) throw new RouterException(fault.InnerText);
            if(xml.SelectSingleNode("//*[local-name()='"+action+"Response']")==null) throw new RouterException("invalid_response");
            return xml;
        }
        private static string Value(XmlDocument xml,string name) {
            XmlNode node=xml.SelectSingleNode("//*[local-name()='"+name+"']");
            if(node==null) throw new RouterException("missing_"+name); return node.InnerText;
        }
        public static Task<RouterLease> OpenAsync(string lan, string gateway, string client, int port) {
            return Task.Factory.StartNew(delegate { return Open(Discover(lan,gateway),gateway,client,port,300); },TaskCreationOptions.LongRunning);
        }
        // Explicit endpoint is also used by the loopback SOAP fixture. No credentials are sent.
        public static RouterLease Open(Uri uri,string gateway,string client,int port,int leaseSeconds) {
            ValidateUrl(uri.AbsoluteUri,gateway);
            IPAddress address=IPAddress.Parse(client);
            if(address.AddressFamily!=AddressFamily.InterNetworkV6 || address.IsIPv6Multicast || address.IsIPv6LinkLocal ||
                address.Equals(IPAddress.IPv6Any) || port<1024 || port>65535 || leaseSeconds<2 || leaseSeconds>3600) throw new ArgumentException("Invalid pinhole scope");
            RouterLease lease=new RouterLease(uri,leaseSeconds);
            XmlDocument state=Soap(uri,"GetFirewallStatus","");
            if(Value(state,"FirewallEnabled")=="0") { lease.FirewallDisabled=true; return lease; }
            if(Value(state,"InboundPinholeAllowed")!="1") throw new RouterException("703");
            XmlDocument created=Soap(uri,"AddPinhole","<RemoteHost></RemoteHost><RemotePort>0</RemotePort><InternalClient>"+address+"</InternalClient><InternalPort>"+port+"</InternalPort><Protocol>6</Protocol><LeaseTime>"+leaseSeconds+"</LeaseTime>");
            int unique;
            if(!int.TryParse(Value(created,"UniqueID"),out unique) || unique<0 || unique>65535) throw new RouterException("invalid_id");
            lease.id=unique; lease.expires=DateTime.UtcNow.AddSeconds(leaseSeconds);
            lease.renewal=new Timer(lease.Renew,null,Math.Max(1000,leaseSeconds*400),Math.Max(1000,leaseSeconds*400));
            return lease;
        }
        private void Renew(object ignored) {
            lock(requestGate) {
                lock(gate) { if(disposed) return; }
                try {
                    Soap(control,"UpdatePinhole","<UniqueID>"+id+"</UniqueID><NewLeaseTime>"+seconds+"</NewLeaseTime>");
                    lock(gate) { expires=DateTime.UtcNow.AddSeconds(seconds); error=""; Renewals++; }
                }
                catch(RouterException e) { lock(gate) error=e.Code; }
                catch(Exception) { lock(gate) error="renewal_failed"; }
            }
        }
        public void Dispose() {
            lock(gate) {
                if(disposed) return; disposed=true; if(renewal!=null) renewal.Dispose();
            }
            lock(requestGate) if(id>=0) { try { Soap(control,"DeletePinhole","<UniqueID>"+id+"</UniqueID>"); } catch(Exception) { lock(gate) error="cleanup_failed_expires_automatically"; } }
        }
    }
}
