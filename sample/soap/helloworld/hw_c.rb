require 'soap/rpc/driver'

s = SOAP::RPC::Driver.new('http://localhost:2000/', 'urn:hws')
s.add_method("hello_world", "from")

p s.hello_world(self.to_s)
