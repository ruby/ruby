require 'drbtest'

begin
  require 'drb/ssl'
rescue LoadError
end

if Object.const_defined?("OpenSSL")


class DRbSSLService < DRbService
  %w(ut_drb_drbssl.rb ut_array_drbssl.rb).each do |nm|
    DRb::ExtServManager.command[nm] = "#{@@ruby} #{@@dir}/#{nm}"
  end
  config = Hash.new

  config[:SSLVerifyMode] = OpenSSL::SSL::VERIFY_PEER
  config[:SSLVerifyCallback] = lambda{ |ok,x509_store|
    true
  }
  begin
    data = open("sample.key"){|io| io.read }
    config[:SSLPrivateKey] = OpenSSL::PKey::RSA.new(data)
    data = open("sample.crt"){|io| io.read }
    config[:SSLCertificate] = OpenSSL::X509::Certificate.new(data)
  rescue
    # $stderr.puts "Switching to use self-signed certificate"
    config[:SSLCertName] =
      [ ["C","JP"], ["O","Foo.DRuby.Org"], ["CN", "Sample"] ]
  end

  uri = ARGV.shift if $0 == __FILE__
  @server = DRb::DRbServer.new(uri || 'drbssl://:0', @@manager, config)
end

class TestDRbSSLCore < Test::Unit::TestCase
  include DRbCore
  def setup
    @ext = DRbSSLService.manager.service('ut_drb_drbssl.rb')
    @there = @ext.front
  end

  def test_02_unknown
  end

  def test_01_02_loop
  end

  def test_05_eq
  end

  def test_06_timeout
    ten = Onecky.new(3)
    assert_raises(TimeoutError) do
      @there.do_timeout(ten)
    end
    assert_raises(TimeoutError) do
      @there.do_timeout(ten)
    end
    sleep 3
  end

end

class TestDRbSSLAry < Test::Unit::TestCase
  include DRbAry
  def setup
    @ext = DRbSSLService.manager.service('ut_array_drbssl.rb')
    @there = @ext.front
  end
end


end
