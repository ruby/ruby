require 'http-access2'
require 'soap/rpc/driver'

# setup driver
url = "https://localhost:17443/"
client = SOAP::RPC::Driver.new(url, 'urn:sslhelloworld')
client.add_method("hello_world", "from")
# load SSL properties
client.loadproperty('files/sslclient.properties')

# SOAP over SSL
p client.hello_world(__FILE__)
