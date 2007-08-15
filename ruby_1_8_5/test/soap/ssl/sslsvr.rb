require 'webrick/https'
require 'logger'
require 'rbconfig'

require 'soap/rpc/httpserver'

class HelloWorldServer < SOAP::RPC::HTTPServer
private

  def on_init
    self.level = Logger::Severity::FATAL
    @default_namespace = 'urn:ssltst'
    add_method(self, 'hello_world', 'from')
  end

  def hello_world(from)
    "Hello World, from #{ from }"
  end
end


if $0 == __FILE__
  PORT = 17171
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
    :Port => PORT,
    :AccessLog => [],
    :SSLEnable => true,
    :SSLCACertificateFile => File.join(DIR, 'ca.cert'),
    :SSLCertificate => cert('server.cert'),
    :SSLPrivateKey => key('server.key'),
    :SSLVerifyClient => nil, #OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT|OpenSSL::SSL::VERIFY_PEER,
    :SSLClientCA => cert('ca.cert'),
    :SSLCertName => nil
  )
  t = Thread.new {
    Thread.current.abort_on_exception = true
    $server.start
  }
  STDOUT.sync = true
  puts $$
  t.join
end
