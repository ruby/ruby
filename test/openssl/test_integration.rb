begin
  require "openssl"
rescue LoadError
end
require "test/unit"
require 'net/https'

class TestIntegration < Test::Unit::TestCase
  def path(file)
    File.expand_path(file, File.dirname(__FILE__))
  end

  # JRUBY-2471
  def _test_drb
    config = {
      :SSLVerifyMode => OpenSSL::SSL::VERIFY_PEER,
      :SSLCACertificateFile => File.join(File.dirname(__FILE__), "fixture", "cacert.pem"),
      :SSLPrivateKey => OpenSSL::PKey::RSA.new(File.read(File.join(File.dirname(__FILE__), "fixture", "localhost_keypair.pem"))),
      :SSLCertificate => OpenSSL::X509::Certificate.new(File.read(File.join(File.dirname(__FILE__), "fixture", "cert_localhost.pem"))),
    }
    p config
    DRb.start_service(nil, nil, config)
  end

  # JRUBY-2913
  # Warning - this test actually uses the internet connection.
  # If there is no connection, it will fail.
  def test_ca_path_name
    uri = URI.parse('https://www.amazon.com')
    http = Net::HTTP.new(uri.host, uri.port)
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.ca_path = path("fixture/ca_path/")
    http.use_ssl = true
    response = http.start do |s|
      assert s.get(uri.request_uri).length > 0
    end
  end

  # Warning - this test actually uses the internet connection.
  # If there is no connection, it will fail.
  def test_ssl_verify
    uri = URI.parse('https://www.amazon.com/')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    # right trust anchor for www.amazon.com
    http.ca_file = path('fixture/verisign.pem')
    response = http.start do |s|
      assert s.get(uri.request_uri).length > 0
    end
    # wrong trust anchor for www.amazon.com
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.ca_file = path('fixture/verisign_c3.pem')
    assert_raise(OpenSSL::SSL::SSLError) do
      # it must cause SSLError for verification failure.
      response = http.start do |s|
        s.get(uri.request_uri)
      end
    end
    # round trip
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.ca_file = path('fixture/verisign.pem')
    response = http.start do |s|
      assert s.get(uri.request_uri).length > 0
    end
  end

  # Warning - this test actually uses the internet connection.
  # If there is no connection, it will fail.
  def test_pathlen_does_not_appear
    uri = URI.parse('https://www.paypal.com/')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    # right trust anchor for www.amazon.com
    http.ca_file = path('fixture/verisign_c3.pem')
    response = http.start do |s|
      assert s.get(uri.request_uri).length > 0
    end
  end

  # JRUBY-2178 and JRUBY-1307
  # Warning - this test actually uses the internet connection.
  # If there is no connection, it will fail.
  # This test generally throws an exception
  # about illegal_parameter when
  # it can't use the cipher string correctly
  def test_cipher_strings
    socket = TCPSocket.new('rubyforge.org', 443)
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.cert_store = OpenSSL::X509::Store.new
    ctx.verify_mode = 0
    ctx.cert = nil
    ctx.key = nil
    ctx.client_ca = nil
    ctx.ciphers = "ALL:!ADH:!LOW:!EXP:!MD5:@STRENGTH"

    ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, ctx)
    ssl_socket.connect
    ssl_socket.close
  end

  # JRUBY-1194
  def test_des_encryption
    iv  = "IVIVIVIV"
    key = "KEYKEYKE"
    alg = "des"
    str = "string abc foo bar baxz"
        
    cipher = OpenSSL::Cipher::Cipher.new(alg)
    cipher.encrypt
    cipher.key = key
    cipher.iv = iv
    cipher.padding = 32
    cipher.key = key
    cipher.iv = iv
    
    encrypted = cipher.update(str)
    encrypted << cipher.final
 
    assert_equal "\253\305\306\372;\374\235\302\357/\006\360\355XO\232\312S\356* #\227\217", encrypted
  end
  
  def _test_perf_of_nil
# require 'net/https'
# require 'benchmark'

# def request(data)
#   connection = Net::HTTP.new("www.google.com", 443)
#   connection.use_ssl = true
#   connection.verify_mode = OpenSSL::SSL::VERIFY_NONE
#   connection.start do |connection|
#     connection.request_post("/tbproxy/spell?lang=en", data, { 'User-Agent' => "Test", 'Accept' => 'text/xml' })
#   end
# end

# puts "is not: #{Benchmark.measure { request("") }.to_s.chomp}"
# puts "is nil: #{Benchmark.measure { request(nil) }.to_s.chomp}"
  end
end
