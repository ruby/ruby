require 'soap/rpc/driver'

server = ARGV.shift || 'http://localhost:7000/'
# server = 'http://localhost:8808/server.cgi'

# client which accesses application scope servant.
app = SOAP::RPC::Driver.new(server,
  'http://tempuri.org/applicationScopeService')
app.add_method('push', 'value')
app.add_method('pop')

# client which accesses request scope servant must send SOAPAction to identify
# the service.
req = SOAP::RPC::Driver.new(server,
  'http://tempuri.org/requestScopeService')
req.add_method_with_soapaction('push',
  'http://tempuri.org/requestScopeService', 'value')
req.add_method_with_soapaction('pop',
  'http://tempuri.org/requestScopeService')

# exec
app.push(1)
app.push(2)
app.push(3)
p app.pop
p app.pop
p app.pop

req.push(1)
req.push(2)
req.push(3)
p req.pop
p req.pop
p req.pop
