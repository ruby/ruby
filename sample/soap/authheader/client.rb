require 'soap/rpc/driver'
require 'soap/header/simplehandler'

server = ARGV.shift || 'http://localhost:7000/'

class ClientAuthHeaderHandler < SOAP::Header::SimpleHandler
  MyHeaderName = XSD::QName.new("http://tempuri.org/authHeader", "auth")

  def initialize(userid, passwd)
    super(MyHeaderName)
    @sessionid = nil
    @userid = userid
    @passwd = passwd
    @mustunderstand = true
  end

  def on_simple_outbound
    if @sessionid
      { "sessionid" => @sessionid }
    else
      { "userid" => @userid, "passwd" => @passwd }
    end
  end

  def on_simple_inbound(my_header, mustunderstand)
    @sessionid = my_header["sessionid"]
  end
end

ns = 'http://tempuri.org/authHeaderPort'
serv = SOAP::RPC::Driver.new(server, ns)
serv.add_method('deposit', 'amt')
serv.add_method('withdrawal', 'amt')

serv.headerhandler << ClientAuthHeaderHandler.new('NaHi', 'passwd')

serv.wiredump_dev = STDOUT

p serv.deposit(150)
p serv.withdrawal(120)
