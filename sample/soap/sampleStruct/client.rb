require 'soap/rpc/driver'

require 'iSampleStruct'

server = ARGV.shift || 'http://localhost:7000/'
# server = 'http://localhost:8808/server.cgi'

drv = SOAP::RPC::Driver.new(server, SampleStructServiceNamespace)
drv.wiredump_dev = STDERR
drv.add_method('hi', 'sampleStruct')

o1 = SampleStruct.new
puts "Sending struct: #{ o1.inspect }"
puts
o2 = drv.hi(o1)
puts "Received (wrapped): #{ o2.inspect }"
