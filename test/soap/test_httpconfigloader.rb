require 'test/unit'
require 'soap/httpconfigloader'
require 'soap/rpc/driver'

if defined?(HTTPAccess2)

module SOAP


class TestHTTPConfigLoader < Test::Unit::TestCase
  DIR = File.dirname(File.expand_path(__FILE__))

  def setup
    @client = SOAP::RPC::Driver.new(nil, nil)
  end

  def test_property
    testpropertyname = File.join(DIR, 'soapclient.properties')
    File.open(testpropertyname, "w") do |f|
      f <<<<__EOP__
protocol.http.ssl_config.verify_mode = OpenSSL::SSL::VERIFY_PEER
# depth: 1 causes an error (intentional)
protocol.http.ssl_config.verify_depth = 1
protocol.http.ssl_config.ciphers = ALL
__EOP__
    end
    begin
      @client.loadproperty(testpropertyname)
      assert_equal('ALL', @client.options['protocol.http.ssl_config.ciphers'])
    ensure
      File.unlink(testpropertyname)
    end
  end
end


end

end
