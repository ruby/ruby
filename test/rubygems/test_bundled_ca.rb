# frozen_string_literal: false
require 'rubygems/test_case'
require 'net/https'
require 'rubygems/request'

# = Testing Bundled CA
#
# The tested hosts are explained in detail here: https://github.com/rubygems/rubygems/commit/5e16a5428f973667cabfa07e94ff939e7a83ebd9
#
class TestBundledCA < Gem::TestCase

  THIS_FILE = File.expand_path __FILE__

  def bundled_certificate_store
    store = OpenSSL::X509::Store.new

    ssl_cert_glob =
      File.expand_path '../../../lib/rubygems/ssl_certs/*.pem', THIS_FILE

    Dir[ssl_cert_glob].each do |ssl_cert|
      store.add_file ssl_cert
    end

    store
  end

  def assert_https(host)
    if self.respond_to? :_assertions # minitest <= 4
      self._assertions += 1
    else # minitest >= 5
      self.assertions += 1
    end
    http = Net::HTTP.new(host, 443)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.cert_store = bundled_certificate_store
    http.get('/')
  rescue Errno::ENOENT, Errno::ETIMEDOUT
    skip "#{host} seems offline, I can't tell whether ssl would work."
  rescue OpenSSL::SSL::SSLError => e
    # Only fail for certificate verification errors
    if e.message =~ /certificate verify failed/
      flunk "#{host} is not verifiable using the included certificates. Error was: #{e.message}"
    end
    raise
  end

  def test_accessing_rubygems
    assert_https('rubygems.org')
  end

  def test_accessing_fastly
    assert_https('rubygems.global.ssl.fastly.net')
  end

end if ENV['TRAVIS']

