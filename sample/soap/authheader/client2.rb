require 'soap/rpc/driver'
require 'soap/header/simplehandler'

server = ARGV.shift || 'http://localhost:7000/'

class ClientAuthHeaderHandler < SOAP::Header::SimpleHandler
  MyHeaderName = XSD::QName.new("http://tempuri.org/authHeader", "auth")

  attr_accessor :sessionid

  def initialize
    super(MyHeaderName)
    @sessionid = nil
  end

  def on_simple_outbound
    if @sessionid
      { "sessionid" => @sessionid }
    end
  end

  def on_simple_inbound(my_header, mustunderstand)
    @sessionid = my_header["sessionid"]
  end
end

ns = 'http://tempuri.org/authHeaderPort'
serv = SOAP::RPC::Driver.new(server, ns)
serv.add_method('login', 'userid', 'passwd')
serv.add_method('deposit', 'amt')
serv.add_method('withdrawal', 'amt')

h = ClientAuthHeaderHandler.new

serv.headerhandler << h

serv.wiredump_dev = STDOUT

sessionid = serv.login('NaHi', 'passwd')
h.sessionid = sessionid
p serv.deposit(150)
p serv.withdrawal(120)
