require 'soap/rpc/driver'
require 'soap/attachment'

server = 'http://localhost:7000/'
driver = SOAP::RPC::Driver.new(server, 'http://www.acmetron.com/soap')
driver.wiredump_dev = STDERR
driver.add_method('get_file')
driver.add_method('put_file', 'name', 'file')

p driver.get_file
file = File.open($0)
attach = SOAP::Attachment.new(file)
p driver.put_file($0, attach)
