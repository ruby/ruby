require 'soap/rpc/driver'

s = SOAP::RPC::Driver.new('http://localhost:2000/', 'urn:hws')
s.add_method("hello_world", "from")
#s.wiredump_dev = STDOUT        # care about binary output.
s.streamhandler.accept_encoding_gzip = true

p s.hello_world(self.to_s)
