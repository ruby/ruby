require 'test_drb'
require 'drb/ssl'

class TestService
  @@scripts = %w(ut_drb_drbssl.rb ut_array_drbssl.rb)
end

class DRbXCoreTest < DRbCoreTest
  def setup
    @ext = $manager.service('ut_drb_drbssl.rb')
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
    assert_exception(TimeoutError) do
      @there.do_timeout(ten)
    end
    assert_exception(TimeoutError) do
      @there.do_timeout(ten)
    end
    sleep 3
  end

end

class DRbXAryTest < DRbAryTest
  def setup
    @ext = $manager.service('ut_array_drbssl.rb')
    @there = @ext.front
  end
end

if __FILE__ == $0
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
    $stderr.puts "Switching to use self-signed certificate"
    config[:SSLCertName] =
      [ ["C","JP"], ["O","Foo.DRuby.Org"], ["CN", "Sample"] ]
  end

  $testservice = TestService.new(ARGV.shift || 'drbssl://:0', config)
  $manager = $testservice.manager
  RUNIT::CUI::TestRunner.run(DRbXCoreTest.suite)
  RUNIT::CUI::TestRunner.run(DRbXAryTest.suite)
  # exit!
end
