require 'soap/rpc/httpserver'
require 'webrick/https'
require 'logger'

class HelloWorldServer < SOAP::RPC::HTTPServer
private

  def on_init
    @default_namespace = 'urn:sslhelloworld'
    add_method(self, 'hello_world', 'from')
  end

  def hello_world(from)
    "Hello World, from #{ from }"
  end
end


if $0 == __FILE__
  DIR = File.dirname(File.expand_path(__FILE__))

  def cert(filename)
    OpenSSL::X509::Certificate.new(File.open(File.join(DIR, filename)) { |f|
      f.read
    })
  end

  def key(filename)
    OpenSSL::PKey::RSA.new(File.open(File.join(DIR, filename)) { |f|
      f.read
    })
  end

  $server = HelloWorldServer.new(
    :BindAddress => "0.0.0.0",
    :Port => 17443,
    :AccessLog => [],
    :SSLEnable => true,
    :SSLCACertificateFile => File.join(DIR, 'files/ca.cert'),
    :SSLCertificate => cert('files/server.cert'),
    :SSLPrivateKey => key('files/server.key'),
    :SSLVerifyClient => nil,
    :SSLCertName => nil
  )
  trap(:INT) do
    $server.shutdown
  end
  $server.start
end
