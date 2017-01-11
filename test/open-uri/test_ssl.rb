# frozen_string_literal: true
require 'test/unit'
require 'open-uri'
require 'stringio'
require 'webrick'
begin
  require 'openssl'
  require 'webrick/https'
rescue LoadError
end
require 'webrick/httpproxy'

class TestOpenURISSL < Test::Unit::TestCase
end

class TestOpenURISSL
  NullLog = Object.new
  def NullLog.<<(arg)
  end

  def with_https(log_tester=lambda {|log| assert_equal([], log) })
    log = []
    logger = WEBrick::Log.new(log, WEBrick::BasicLog::WARN)
    Dir.mktmpdir {|dr|
      srv = WEBrick::HTTPServer.new({
        :DocumentRoot => dr,
        :ServerType => Thread,
        :Logger => logger,
        :AccessLog => [[NullLog, ""]],
        :SSLEnable => true,
        :SSLCertificate => OpenSSL::X509::Certificate.new(SERVER_CERT),
        :SSLPrivateKey => OpenSSL::PKey::RSA.new(SERVER_KEY),
        :SSLTmpDhCallback => proc { OpenSSL::PKey::DH.new(DHPARAMS) },
        :BindAddress => '127.0.0.1',
        :Port => 0})
      _, port, _, host = srv.listeners[0].addr
      threads = []
      server_thread = srv.start
      threads << Thread.new {
        server_thread.join
        if log_tester
          log_tester.call(log)
        end
      }
      threads << Thread.new {
        begin
          yield srv, dr, "https://#{host}:#{port}", server_thread, log, threads
        ensure
          srv.shutdown
        end
      }
      assert_join_threads(threads)
    }
  ensure
    WEBrick::Utils::TimeoutHandler.terminate
  end

  def setup
    @proxies = %w[http_proxy HTTP_PROXY https_proxy HTTPS_PROXY ftp_proxy FTP_PROXY no_proxy]
    @old_proxies = @proxies.map {|k| ENV[k] }
    @proxies.each {|k| ENV[k] = nil }
  end

  def teardown
    @proxies.each_with_index {|k, i| ENV[k] = @old_proxies[i] }
  end

  def setup_validation(srv, dr)
    cacert_filename = "#{dr}/cacert.pem"
    open(cacert_filename, "w") {|f| f << CA_CERT }
    srv.mount_proc("/data", lambda { |req, res| res.body = "ddd" } )
    cacert_filename
  end

  def test_validation_success
    with_https {|srv, dr, url|
      cacert_filename = setup_validation(srv, dr)
      open("#{url}/data", :ssl_ca_cert => cacert_filename) {|f|
        assert_equal("200", f.status[0])
        assert_equal("ddd", f.read)
      }
    }
  end

  def test_validation_noverify
    with_https {|srv, dr, url|
      setup_validation(srv, dr)
      open("#{url}/data", :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE) {|f|
        assert_equal("200", f.status[0])
        assert_equal("ddd", f.read)
      }
    }
  end

  def test_validation_failure
    unless /mswin|mingw/ =~ RUBY_PLATFORM
      # on Windows, Errno::ECONNRESET will be raised, and it'll be eaten by
      # WEBrick
      log_tester = lambda {|server_log|
        assert_equal(1, server_log.length)
        assert_match(/ERROR OpenSSL::SSL::SSLError:/, server_log[0])
      }
    end
    with_https(log_tester) {|srv, dr, url, server_thread, server_log|
      setup_validation(srv, dr)
      assert_raise(OpenSSL::SSL::SSLError) { open("#{url}/data") {} }
    }
  end

  def with_https_proxy(proxy_log_tester=lambda {|proxy_log, proxy_access_log| assert_equal([], proxy_log) })
    proxy_log = []
    proxy_logger = WEBrick::Log.new(proxy_log, WEBrick::BasicLog::WARN)
    with_https {|srv, dr, url, server_thread, server_log, threads|
      srv.mount_proc("/proxy", lambda { |req, res| res.body = "proxy" } )
      cacert_filename = "#{dr}/cacert.pem"
      open(cacert_filename, "w") {|f| f << CA_CERT }
      cacert_directory = "#{dr}/certs"
      Dir.mkdir cacert_directory
      hashed_name = "%08x.0" % OpenSSL::X509::Certificate.new(CA_CERT).subject.hash
      open("#{cacert_directory}/#{hashed_name}", "w") {|f| f << CA_CERT }
      proxy = WEBrick::HTTPProxyServer.new({
        :ServerType => Thread,
        :Logger => proxy_logger,
        :AccessLog => [[proxy_access_log=[], WEBrick::AccessLog::COMMON_LOG_FORMAT]],
        :BindAddress => '127.0.0.1',
        :Port => 0})
      _, proxy_port, _, proxy_host = proxy.listeners[0].addr
      proxy_thread = proxy.start
      threads << Thread.new {
        proxy_thread.join
        if proxy_log_tester
          proxy_log_tester.call(proxy_log, proxy_access_log)
        end
      }
      begin
        yield srv, dr, url, cacert_filename, cacert_directory, proxy_host, proxy_port
      ensure
        proxy.shutdown
      end
    }
  end

  def test_proxy_cacert_file
    url = nil
    proxy_log_tester = lambda {|proxy_log, proxy_access_log|
      assert_equal(1, proxy_access_log.length)
      assert_match(%r[CONNECT #{url.sub(%r{\Ahttps://}, '')} ], proxy_access_log[0])
      assert_equal([], proxy_log)
    }
    with_https_proxy(proxy_log_tester) {|srv, dr, url_, cacert_filename, cacert_directory, proxy_host, proxy_port|
      url = url_
      open("#{url}/proxy", :proxy=>"http://#{proxy_host}:#{proxy_port}/", :ssl_ca_cert => cacert_filename) {|f|
        assert_equal("200", f.status[0])
        assert_equal("proxy", f.read)
      }
    }
  end

  def test_proxy_cacert_dir
    url = nil
    proxy_log_tester = lambda {|proxy_log, proxy_access_log|
      assert_equal(1, proxy_access_log.length)
      assert_match(%r[CONNECT #{url.sub(%r{\Ahttps://}, '')} ], proxy_access_log[0])
      assert_equal([], proxy_log)
    }
    with_https_proxy(proxy_log_tester) {|srv, dr, url_, cacert_filename, cacert_directory, proxy_host, proxy_port|
      url = url_
      open("#{url}/proxy", :proxy=>"http://#{proxy_host}:#{proxy_port}/", :ssl_ca_cert => cacert_directory) {|f|
        assert_equal("200", f.status[0])
        assert_equal("proxy", f.read)
      }
    }
  end

end if defined?(OpenSSL::SSL)

if defined?(OpenSSL::SSL)
# cp /etc/ssl/openssl.cnf . # I copied from OpenSSL 1.0.2h source

# mkdir demoCA demoCA/private demoCA/newcerts
# touch demoCA/index.txt
# echo 00 > demoCA/serial
# openssl genrsa -des3 -out demoCA/private/cakey.pem 1024
# openssl req -new -key demoCA/private/cakey.pem -out demoCA/careq.pem -subj "/C=JP/ST=Tokyo/O=RubyTest/CN=Ruby Test CA"
# # basicConstraints=CA:TRUE is required; the default openssl.cnf has it in [v3_ca]
# openssl ca -config openssl.cnf -extensions v3_ca -out demoCA/cacert.pem -startdate 090101000000Z -enddate 491231235959Z -batch -keyfile demoCA/private/cakey.pem -selfsign -infiles demoCA/careq.pem

# mkdir server
# openssl genrsa -des3 -out server/server.key 1024
# openssl req -new -key server/server.key -out server/csr.pem -subj "/C=JP/ST=Tokyo/O=RubyTest/CN=127.0.0.1"
# openssl ca -config openssl.cnf -startdate 090101000000Z -enddate 491231235959Z -in server/csr.pem -keyfile demoCA/private/cakey.pem -cert demoCA/cacert.pem -out server/cert.pem

# demoCA/cacert.pem => TestOpenURISSL::CA_CERT
# server/cert.pem => TestOpenURISSL::SERVER_CERT
# `openssl rsa -in server/server.key -text` => TestOpenURISSL::SERVER_KEY

TestOpenURISSL::CA_CERT = <<'End'
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number: 0 (0x0)
    Signature Algorithm: sha256WithRSAEncryption
        Issuer: C=JP, ST=Tokyo, O=RubyTest, CN=Ruby Test CA
        Validity
            Not Before: Jan  1 00:00:00 2009 GMT
            Not After : Dec 31 23:59:59 2049 GMT
        Subject: C=JP, ST=Tokyo, O=RubyTest, CN=Ruby Test CA
        Subject Public Key Info:
            Public Key Algorithm: rsaEncryption
                Public-Key: (1024 bit)
                Modulus:
                    00:be:74:41:33:c9:1b:e1:12:78:6b:b4:52:2e:ae:
                    b6:e2:1e:58:65:57:2d:cb:07:3f:91:c9:53:7a:e7:
                    2e:68:2c:0c:5d:8b:16:a7:42:4a:5c:6f:c7:aa:44:
                    ff:6d:c6:d7:49:0e:b1:5d:03:5b:51:ce:d5:cc:cd:
                    ab:69:cc:c2:43:76:b1:b2:30:3b:e7:f6:1f:3e:35:
                    1d:21:75:41:96:eb:84:a0:34:6f:a4:5d:70:a2:b2:
                    d5:fe:b9:45:47:a1:e8:ca:e3:b7:bb:4d:37:1c:f3:
                    96:d4:2d:80:85:cd:8e:31:96:53:92:a0:fe:e4:4c:
                    16:47:5e:c8:27:32:70:a8:6b
                Exponent: 65537 (0x10001)
        X509v3 extensions:
            X509v3 Subject Key Identifier:
                71:DB:DC:BA:F6:7F:75:31:7A:ED:AB:8B:48:93:86:94:1A:FF:30:58
            X509v3 Authority Key Identifier:
                keyid:71:DB:DC:BA:F6:7F:75:31:7A:ED:AB:8B:48:93:86:94:1A:FF:30:58

            X509v3 Basic Constraints:
                CA:TRUE
    Signature Algorithm: sha256WithRSAEncryption
         91:1c:45:a5:c0:4e:fc:54:39:62:33:80:7d:03:c1:b8:51:f7:
         56:83:6c:a3:15:50:cf:92:a0:77:a3:34:16:b5:30:f0:33:5a:
         be:6a:ac:17:87:70:f8:4e:4d:49:ac:8b:84:fd:e5:0f:15:d7:
         9a:29:cc:a9:f5:97:f5:13:2a:86:3b:2d:f4:b7:b4:a2:7c:e1:
         0e:2a:ff:91:64:31:8f:12:cc:99:bf:e1:de:8f:6f:7c:1b:e4:
         cc:56:c8:bb:85:c9:ba:df:7f:07:7a:cd:03:22:2c:b6:f8:06:
         35:72:72:b8:52:eb:62:15:85:2b:8f:8c:bc:27:3c:8b:de:32:
         db:95
-----BEGIN CERTIFICATE-----
MIICVDCCAb2gAwIBAgIBADANBgkqhkiG9w0BAQsFADBHMQswCQYDVQQGEwJKUDEO
MAwGA1UECAwFVG9reW8xETAPBgNVBAoMCFJ1YnlUZXN0MRUwEwYDVQQDDAxSdWJ5
IFRlc3QgQ0EwHhcNMDkwMTAxMDAwMDAwWhcNNDkxMjMxMjM1OTU5WjBHMQswCQYD
VQQGEwJKUDEOMAwGA1UECAwFVG9reW8xETAPBgNVBAoMCFJ1YnlUZXN0MRUwEwYD
VQQDDAxSdWJ5IFRlc3QgQ0EwgZ8wDQYJKoZIhvcNAQEBBQADgY0AMIGJAoGBAL50
QTPJG+ESeGu0Ui6utuIeWGVXLcsHP5HJU3rnLmgsDF2LFqdCSlxvx6pE/23G10kO
sV0DW1HO1czNq2nMwkN2sbIwO+f2Hz41HSF1QZbrhKA0b6RdcKKy1f65RUeh6Mrj
t7tNNxzzltQtgIXNjjGWU5Kg/uRMFkdeyCcycKhrAgMBAAGjUDBOMB0GA1UdDgQW
BBRx29y69n91MXrtq4tIk4aUGv8wWDAfBgNVHSMEGDAWgBRx29y69n91MXrtq4tI
k4aUGv8wWDAMBgNVHRMEBTADAQH/MA0GCSqGSIb3DQEBCwUAA4GBAJEcRaXATvxU
OWIzgH0DwbhR91aDbKMVUM+SoHejNBa1MPAzWr5qrBeHcPhOTUmsi4T95Q8V15op
zKn1l/UTKoY7LfS3tKJ84Q4q/5FkMY8SzJm/4d6Pb3wb5MxWyLuFybrffwd6zQMi
LLb4BjVycrhS62IVhSuPjLwnPIveMtuV
-----END CERTIFICATE-----
End

TestOpenURISSL::SERVER_CERT = <<'End'
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number: 1 (0x1)
    Signature Algorithm: sha256WithRSAEncryption
        Issuer: C=JP, ST=Tokyo, O=RubyTest, CN=Ruby Test CA
        Validity
            Not Before: Jan  1 00:00:00 2009 GMT
            Not After : Dec 31 23:59:59 2049 GMT
        Subject: C=JP, ST=Tokyo, O=RubyTest, CN=127.0.0.1
        Subject Public Key Info:
            Public Key Algorithm: rsaEncryption
                Public-Key: (1024 bit)
                Modulus:
                    00:bb:bd:74:69:53:58:50:24:79:f2:eb:db:8b:97:
                    e4:69:a4:dd:48:0c:40:35:62:42:b3:35:8c:96:2a:
                    62:76:98:b5:2a:e0:f8:78:33:b6:ff:f8:55:bf:44:
                    69:21:d7:b5:0e:bd:8a:dd:31:1b:88:d5:b4:5e:7a:
                    82:e0:ba:99:6c:04:76:e9:ff:e6:f8:f5:06:8e:7e:
                    a4:db:db:eb:43:44:12:a7:ca:ca:2b:aa:5f:83:10:
                    e2:9e:35:55:e8:e8:af:be:c8:7d:bb:c2:d4:aa:c1:
                    1c:57:0b:c0:0c:3a:1d:6e:23:a9:03:26:7c:ea:8c:
                    f0:86:61:ce:f1:ff:42:c7:23
                Exponent: 65537 (0x10001)
        X509v3 extensions:
            X509v3 Basic Constraints:
                CA:FALSE
            Netscape Comment:
                OpenSSL Generated Certificate
            X509v3 Subject Key Identifier:
                7F:17:5A:58:88:96:E1:1F:44:EA:FF:AD:C6:2E:90:E2:95:32:DD:F0
            X509v3 Authority Key Identifier:
                keyid:71:DB:DC:BA:F6:7F:75:31:7A:ED:AB:8B:48:93:86:94:1A:FF:30:58

    Signature Algorithm: sha256WithRSAEncryption
         1c:80:02:67:f0:4e:a8:5a:6a:73:9c:de:75:ad:7d:2e:e9:ce:
         c3:2e:cd:70:b4:21:d9:42:0d:7c:0e:77:9e:97:91:13:02:77:
         4a:cd:f6:fc:26:3d:42:2e:08:85:05:10:df:3a:5f:f0:77:85:
         44:29:41:dd:03:6b:eb:e7:c8:89:8e:d1:57:a8:ac:43:c8:85:
         c3:95:64:9f:a5:6e:e9:2e:6e:06:45:21:36:ec:d5:79:f5:0e:
         a8:53:b5:f7:02:b0:59:12:e3:ae:73:25:fd:18:ab:23:b2:fc:
         a9:f9:60:e5:a7:d8:ba:0f:db:be:17:81:25:90:fd:7a:21:cb:
         fa:8b
-----BEGIN CERTIFICATE-----
MIICfDCCAeWgAwIBAgIBATANBgkqhkiG9w0BAQsFADBHMQswCQYDVQQGEwJKUDEO
MAwGA1UECAwFVG9reW8xETAPBgNVBAoMCFJ1YnlUZXN0MRUwEwYDVQQDDAxSdWJ5
IFRlc3QgQ0EwHhcNMDkwMTAxMDAwMDAwWhcNNDkxMjMxMjM1OTU5WjBEMQswCQYD
VQQGEwJKUDEOMAwGA1UECAwFVG9reW8xETAPBgNVBAoMCFJ1YnlUZXN0MRIwEAYD
VQQDDAkxMjcuMC4wLjEwgZ8wDQYJKoZIhvcNAQEBBQADgY0AMIGJAoGBALu9dGlT
WFAkefLr24uX5Gmk3UgMQDViQrM1jJYqYnaYtSrg+Hgztv/4Vb9EaSHXtQ69it0x
G4jVtF56guC6mWwEdun/5vj1Bo5+pNvb60NEEqfKyiuqX4MQ4p41Vejor77IfbvC
1KrBHFcLwAw6HW4jqQMmfOqM8IZhzvH/QscjAgMBAAGjezB5MAkGA1UdEwQCMAAw
LAYJYIZIAYb4QgENBB8WHU9wZW5TU0wgR2VuZXJhdGVkIENlcnRpZmljYXRlMB0G
A1UdDgQWBBR/F1pYiJbhH0Tq/63GLpDilTLd8DAfBgNVHSMEGDAWgBRx29y69n91
MXrtq4tIk4aUGv8wWDANBgkqhkiG9w0BAQsFAAOBgQAcgAJn8E6oWmpznN51rX0u
6c7DLs1wtCHZQg18Dneel5ETAndKzfb8Jj1CLgiFBRDfOl/wd4VEKUHdA2vr58iJ
jtFXqKxDyIXDlWSfpW7pLm4GRSE27NV59Q6oU7X3ArBZEuOucyX9GKsjsvyp+WDl
p9i6D9u+F4ElkP16Icv6iw==
-----END CERTIFICATE-----
End

TestOpenURISSL::SERVER_KEY = <<'End'
Private-Key: (1024 bit)
modulus:
    00:bb:bd:74:69:53:58:50:24:79:f2:eb:db:8b:97:
    e4:69:a4:dd:48:0c:40:35:62:42:b3:35:8c:96:2a:
    62:76:98:b5:2a:e0:f8:78:33:b6:ff:f8:55:bf:44:
    69:21:d7:b5:0e:bd:8a:dd:31:1b:88:d5:b4:5e:7a:
    82:e0:ba:99:6c:04:76:e9:ff:e6:f8:f5:06:8e:7e:
    a4:db:db:eb:43:44:12:a7:ca:ca:2b:aa:5f:83:10:
    e2:9e:35:55:e8:e8:af:be:c8:7d:bb:c2:d4:aa:c1:
    1c:57:0b:c0:0c:3a:1d:6e:23:a9:03:26:7c:ea:8c:
    f0:86:61:ce:f1:ff:42:c7:23
publicExponent: 65537 (0x10001)
privateExponent:
    00:af:3a:ec:17:0a:f5:d9:07:d2:d3:4c:15:c5:3b:
    66:b4:bc:6e:d5:ba:a9:8b:aa:45:3b:63:f5:ee:8b:
    6d:0f:e9:04:e0:1a:cf:8f:d2:25:32:d1:a5:a7:3a:
    c1:2e:17:5a:25:82:00:c4:e7:fb:1d:42:ea:71:6c:
    c4:0f:e1:db:23:ff:1e:d6:c8:d6:60:ca:2d:06:fc:
    54:3c:03:d4:09:96:bb:38:7a:22:a1:61:2c:f7:d0:
    d0:90:6c:9f:61:ba:61:30:5a:aa:64:ad:43:3a:53:
    38:e8:ba:cc:8c:51:3e:68:3e:3a:6a:0f:5d:5d:e0:
    d6:df:f2:54:93:d3:14:22:a1
prime1:
    00:e8:ec:11:fe:e6:2b:23:21:29:d5:40:a6:11:ec:
    4c:ae:4d:08:2a:71:18:ac:d1:3e:40:2f:12:41:59:
    12:09:e2:f7:c2:d7:6b:0a:96:0a:06:e3:90:6a:4e:
    b2:eb:25:b7:09:68:e9:13:ab:d0:5a:29:7a:e4:72:
    1a:ee:46:a0:8b
prime2:
    00:ce:57:5e:31:e9:c9:a8:5b:1f:55:af:67:e2:49:
    2a:af:90:b6:02:c0:32:2f:ca:ae:1e:de:47:81:73:
    a8:f8:37:53:70:93:24:62:77:d4:b8:80:30:9f:65:
    26:20:46:ae:5a:65:6e:6d:af:68:4c:8d:e8:3c:f3:
    d1:d1:d9:6e:c9
exponent1:
    03:f1:02:b8:f2:82:26:5d:08:4d:30:83:de:e7:c5:
    c0:69:53:4b:0c:90:e3:53:c3:1e:e8:ed:01:28:15:
    b3:0f:21:2c:2d:e3:04:d1:d7:27:98:b0:37:ec:4f:
    00:c5:a9:9c:42:27:37:8a:ff:c2:96:d3:1a:8c:87:
    c2:22:75:d3
exponent2:
    6f:17:32:ab:84:c7:01:51:2d:e9:9f:ea:3a:36:52:
    38:fb:9c:42:96:df:6e:43:9c:c3:19:c1:3d:bc:db:
    77:e7:b1:90:a6:67:ac:6b:ff:a6:e5:bd:47:d3:d9:
    56:ff:36:d7:8c:4c:8b:d9:28:3a:2f:1c:9d:d4:57:
    5e:b7:c5:a1
coefficient:
    45:50:47:66:56:e9:21:d9:40:0e:af:3f:f2:05:77:
    ab:e7:08:40:97:88:2a:51:b3:7e:86:b0:b2:03:2e:
    6d:36:3f:46:42:97:7d:5a:a2:93:6c:05:c2:8b:8b:
    2d:af:d5:7d:75:e9:70:f0:2d:21:e3:b9:cf:4d:9a:
    c4:97:e2:79
-----BEGIN RSA PRIVATE KEY-----
MIICXAIBAAKBgQC7vXRpU1hQJHny69uLl+RppN1IDEA1YkKzNYyWKmJ2mLUq4Ph4
M7b/+FW/RGkh17UOvYrdMRuI1bReeoLguplsBHbp/+b49QaOfqTb2+tDRBKnysor
ql+DEOKeNVXo6K++yH27wtSqwRxXC8AMOh1uI6kDJnzqjPCGYc7x/0LHIwIDAQAB
AoGBAK867BcK9dkH0tNMFcU7ZrS8btW6qYuqRTtj9e6LbQ/pBOAaz4/SJTLRpac6
wS4XWiWCAMTn+x1C6nFsxA/h2yP/HtbI1mDKLQb8VDwD1AmWuzh6IqFhLPfQ0JBs
n2G6YTBaqmStQzpTOOi6zIxRPmg+OmoPXV3g1t/yVJPTFCKhAkEA6OwR/uYrIyEp
1UCmEexMrk0IKnEYrNE+QC8SQVkSCeL3wtdrCpYKBuOQak6y6yW3CWjpE6vQWil6
5HIa7kagiwJBAM5XXjHpyahbH1WvZ+JJKq+QtgLAMi/Krh7eR4FzqPg3U3CTJGJ3
1LiAMJ9lJiBGrlplbm2vaEyN6Dzz0dHZbskCQAPxArjygiZdCE0wg97nxcBpU0sM
kONTwx7o7QEoFbMPISwt4wTR1yeYsDfsTwDFqZxCJzeK/8KW0xqMh8IiddMCQG8X
MquExwFRLemf6jo2Ujj7nEKW325DnMMZwT2823fnsZCmZ6xr/6blvUfT2Vb/NteM
TIvZKDovHJ3UV163xaECQEVQR2ZW6SHZQA6vP/IFd6vnCECXiCpRs36GsLIDLm02
P0ZCl31aopNsBcKLiy2v1X116XDwLSHjuc9NmsSX4nk=
-----END RSA PRIVATE KEY-----
End

TestOpenURISSL::DHPARAMS = <<'End'
    DH Parameters: (2048 bit)
        prime:
            00:ec:4e:a4:06:b6:22:ca:f9:8a:00:cc:d0:ee:2f:
            16:bf:05:64:f5:8f:fe:7f:c4:bb:b0:24:cd:ef:5d:
            8a:90:ad:dc:a9:dd:63:84:90:d8:25:ba:d8:78:d5:
            77:91:42:0a:84:fc:56:1e:13:9b:1c:aa:43:d5:1f:
            38:52:92:fe:b3:66:f9:e7:e8:8c:77:a1:a6:2f:b3:
            98:98:d2:13:fc:57:1c:2a:14:dc:bd:e6:9b:54:19:
            99:4f:ce:81:64:a6:32:7f:8e:61:50:5f:45:3a:e5:
            0c:f7:13:f3:b8:ad:d5:77:ca:09:42:f7:d8:30:27:
            7b:2c:f0:b4:b5:a0:04:96:34:0b:47:81:1d:7f:c1:
            3a:62:86:8e:7d:f8:13:7f:9a:b1:8b:09:23:9e:55:
            59:41:cd:f0:86:09:c4:b7:d1:69:54:cb:d0:f5:e9:
            27:c9:e1:81:e4:a1:df:6b:20:1c:df:e8:54:02:f2:
            37:fc:2a:f7:d5:b3:6f:79:7e:70:22:78:79:18:3c:
            75:14:68:4a:05:9f:ac:d4:7f:9a:79:db:9d:0a:6e:
            ec:0a:04:70:bf:c9:4a:59:81:a2:1f:33:9b:4a:66:
            bc:03:ce:8a:1b:e3:03:ec:ba:39:26:ab:90:dc:39:
            41:a1:d8:f7:20:3c:8f:af:12:2f:f7:a9:6f:44:f1:
            6d:03
        generator: 2 (0x2)
-----BEGIN DH PARAMETERS-----
MIIBCAKCAQEA7E6kBrYiyvmKAMzQ7i8WvwVk9Y/+f8S7sCTN712KkK3cqd1jhJDY
JbrYeNV3kUIKhPxWHhObHKpD1R84UpL+s2b55+iMd6GmL7OYmNIT/FccKhTcveab
VBmZT86BZKYyf45hUF9FOuUM9xPzuK3Vd8oJQvfYMCd7LPC0taAEljQLR4Edf8E6
YoaOffgTf5qxiwkjnlVZQc3whgnEt9FpVMvQ9eknyeGB5KHfayAc3+hUAvI3/Cr3
1bNveX5wInh5GDx1FGhKBZ+s1H+aedudCm7sCgRwv8lKWYGiHzObSma8A86KG+MD
7Lo5JquQ3DlBodj3IDyPrxIv96lvRPFtAwIBAg==
-----END DH PARAMETERS-----
End

end
