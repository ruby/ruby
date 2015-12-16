# frozen_string_literal: false
begin
  require "openssl"

  # Disable FIPS mode for tests for installations
  # where FIPS mode would be enabled by default.
  # Has no effect on all other installations.
  OpenSSL.fips_mode=false
rescue LoadError
end
require "test/unit"
require "digest/md5"
require 'tempfile'
require "rbconfig"
require "socket"

module OpenSSL::TestUtils
  TEST_KEY_RSA1024 = OpenSSL::PKey::RSA.new <<-_end_of_pem_
-----BEGIN RSA PRIVATE KEY-----
MIICXgIBAAKBgQDLwsSw1ECnPtT+PkOgHhcGA71nwC2/nL85VBGnRqDxOqjVh7Cx
aKPERYHsk4BPCkE3brtThPWc9kjHEQQ7uf9Y1rbCz0layNqHyywQEVLFmp1cpIt/
Q3geLv8ZD9pihowKJDyMDiN6ArYUmZczvW4976MU3+l54E6lF/JfFEU5hwIDAQAB
AoGBAKSl/MQarye1yOysqX6P8fDFQt68VvtXkNmlSiKOGuzyho0M+UVSFcs6k1L0
maDE25AMZUiGzuWHyaU55d7RXDgeskDMakD1v6ZejYtxJkSXbETOTLDwUWTn618T
gnb17tU1jktUtU67xK/08i/XodlgnQhs6VoHTuCh3Hu77O6RAkEA7+gxqBuZR572
74/akiW/SuXm0SXPEviyO1MuSRwtI87B02D0qgV8D1UHRm4AhMnJ8MCs1809kMQE
JiQUCrp9mQJBANlt2ngBO14us6NnhuAseFDTBzCHXwUUu1YKHpMMmxpnGqaldGgX
sOZB3lgJsT9VlGf3YGYdkLTNVbogQKlKpB8CQQDiSwkb4vyQfDe8/NpU5Not0fII
8jsDUCb+opWUTMmfbxWRR3FBNu8wnym/m19N4fFj8LqYzHX4KY0oVPu6qvJxAkEA
wa5snNekFcqONLIE4G5cosrIrb74sqL8GbGb+KuTAprzj5z1K8Bm0UW9lTjVDjDi
qRYgZfZSL+x1P/54+xTFSwJAY1FxA/N3QPCXCjPh5YqFxAMQs2VVYTfg+t0MEcJD
dPMQD5JX6g5HKnHFg2mZtoXQrWmJSn7p8GJK8yNTopEErA==
-----END RSA PRIVATE KEY-----
  _end_of_pem_

  TEST_KEY_RSA2048 = OpenSSL::PKey::RSA.new <<-_end_of_pem_
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAuV9ht9J7k4NBs38jOXvvTKY9gW8nLICSno5EETR1cuF7i4pN
s9I1QJGAFAX0BEO4KbzXmuOvfCpD3CU+Slp1enenfzq/t/e/1IRW0wkJUJUFQign
4CtrkJL+P07yx18UjyPlBXb81ApEmAB5mrJVSrWmqbjs07JbuS4QQGGXLc+Su96D
kYKmSNVjBiLxVVSpyZfAY3hD37d60uG+X8xdW5v68JkRFIhdGlb6JL8fllf/A/bl
NwdJOhVr9mESHhwGjwfSeTDPfd8ZLE027E5lyAVX9KZYcU00mOX+fdxOSnGqS/8J
DRh0EPHDL15RcJjV2J6vZjPb0rOYGDoMcH+94wIDAQABAoIBAAzsamqfYQAqwXTb
I0CJtGg6msUgU7HVkOM+9d3hM2L791oGHV6xBAdpXW2H8LgvZHJ8eOeSghR8+dgq
PIqAffo4x1Oma+FOg3A0fb0evyiACyrOk+EcBdbBeLo/LcvahBtqnDfiUMQTpy6V
seSoFCwuN91TSCeGIsDpRjbG1vxZgtx+uI+oH5+ytqJOmfCksRDCkMglGkzyfcl0
Xc5CUhIJ0my53xijEUQl19rtWdMnNnnkdbG8PT3LZlOta5Do86BElzUYka0C6dUc
VsBDQ0Nup0P6rEQgy7tephHoRlUGTYamsajGJaAo1F3IQVIrRSuagi7+YpSpCqsW
wORqorkCgYEA7RdX6MDVrbw7LePnhyuaqTiMK+055/R1TqhB1JvvxJ1CXk2rDL6G
0TLHQ7oGofd5LYiemg4ZVtWdJe43BPZlVgT6lvL/iGo8JnrncB9Da6L7nrq/+Rvj
XGjf1qODCK+LmreZWEsaLPURIoR/Ewwxb9J2zd0CaMjeTwafJo1CZvcCgYEAyCgb
aqoWvUecX8VvARfuA593Lsi50t4MEArnOXXcd1RnXoZWhbx5rgO8/ATKfXr0BK/n
h2GF9PfKzHFm/4V6e82OL7gu/kLy2u9bXN74vOvWFL5NOrOKPM7Kg+9I131kNYOw
Ivnr/VtHE5s0dY7JChYWE1F3vArrOw3T00a4CXUCgYEA0SqY+dS2LvIzW4cHCe9k
IQqsT0yYm5TFsUEr4sA3xcPfe4cV8sZb9k/QEGYb1+SWWZ+AHPV3UW5fl8kTbSNb
v4ng8i8rVVQ0ANbJO9e5CUrepein2MPL0AkOATR8M7t7dGGpvYV0cFk8ZrFx0oId
U0PgYDotF/iueBWlbsOM430CgYEAqYI95dFyPI5/AiSkY5queeb8+mQH62sdcCCr
vd/w/CZA/K5sbAo4SoTj8dLk4evU6HtIa0DOP63y071eaxvRpTNqLUOgmLh+D6gS
Cc7TfLuFrD+WDBatBd5jZ+SoHccVrLR/4L8jeodo5FPW05A+9gnKXEXsTxY4LOUC
9bS4e1kCgYAqVXZh63JsMwoaxCYmQ66eJojKa47VNrOeIZDZvd2BPVf30glBOT41
gBoDG3WMPZoQj9pb7uMcrnvs4APj2FIhMU8U15LcPAj59cD6S6rWnAxO8NFK7HQG
4Jxg3JNNf8ErQoCHb1B3oVdXJkmbJkARoDpBKmTCgKtP8ADYLmVPQw==
-----END RSA PRIVATE KEY-----
  _end_of_pem_

  TEST_KEY_DSA256 = OpenSSL::PKey::DSA.new <<-_end_of_pem_
-----BEGIN DSA PRIVATE KEY-----
MIH3AgEAAkEAhk2libbY2a8y2Pt21+YPYGZeW6wzaW2yfj5oiClXro9XMR7XWLkE
9B7XxLNFCS2gmCCdMsMW1HulaHtLFQmB2wIVAM43JZrcgpu6ajZ01VkLc93gu/Ed
AkAOhujZrrKV5CzBKutKLb0GVyVWmdC7InoNSMZEeGU72rT96IjM59YzoqmD0pGM
3I1o4cGqg1D1DfM1rQlnN1eSAkBq6xXfEDwJ1mLNxF6q8Zm/ugFYWR5xcX/3wFiT
b4+EjHP/DbNh9Vm5wcfnDBJ1zKvrMEf2xqngYdrV/3CiGJeKAhRvL57QvJZcQGvn
ISNX5cMzFHRW3Q==
-----END DSA PRIVATE KEY-----
  _end_of_pem_

  TEST_KEY_DSA512 = OpenSSL::PKey::DSA.new <<-_end_of_pem_
-----BEGIN DSA PRIVATE KEY-----
MIH4AgEAAkEA5lB4GvEwjrsMlGDqGsxrbqeFRh6o9OWt6FgTYiEEHaOYhkIxv0Ok
RZPDNwOG997mDjBnvDJ1i56OmS3MbTnovwIVAJgub/aDrSDB4DZGH7UyarcaGy6D
AkB9HdFw/3td8K4l1FZHv7TCZeJ3ZLb7dF3TWoGUP003RCqoji3/lHdKoVdTQNuR
S/m6DlCwhjRjiQ/lBRgCLCcaAkEAjN891JBjzpMj4bWgsACmMggFf57DS0Ti+5++
Q1VB8qkJN7rA7/2HrCR3gTsWNb1YhAsnFsoeRscC+LxXoXi9OAIUBG98h4tilg6S
55jreJD3Se3slps=
-----END DSA PRIVATE KEY-----
  _end_of_pem_

if defined?(OpenSSL::PKey::EC)

  TEST_KEY_EC_P256V1 = OpenSSL::PKey::EC.new <<-_end_of_pem_
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIID49FDqcf1O1eO8saTgG70UbXQw9Fqwseliit2aWhH1oAoGCCqGSM49
AwEHoUQDQgAEFglk2c+oVUIKQ64eZG9bhLNPWB7lSZ/ArK41eGy5wAzU/0G51Xtt
CeBUl+MahZtn9fO1JKdF4qJmS39dXnpENg==
-----END EC PRIVATE KEY-----
  _end_of_pem_

end

  TEST_KEY_DH512_PUB = OpenSSL::PKey::DH.new <<-_end_of_pem_
-----BEGIN DH PARAMETERS-----
MEYCQQDmWXGPqk76sKw/edIOdhAQD4XzjJ+AR/PTk2qzaGs+u4oND2yU5D2NN4wr
aPgwHyJBiK1/ebK3tYcrSKrOoRyrAgEC
-----END DH PARAMETERS-----
  _end_of_pem_

  TEST_KEY_DH1024 = OpenSSL::PKey::DH.new <<-_end_of_pem_
-----BEGIN DH PARAMETERS-----
MIGHAoGBAKnKQ8MNK6nYZzLrrcuTsLxuiJGXoOO5gT+tljOTbHBuiktdMTITzIY0
pFxIvjG05D7HoBZQfrR0c92NGWPkAiCkhQKB8JCbPVzwNLDy6DZ0pmofDKrEsYHG
AQjjxMXhwULlmuR/K+WwlaZPiLIBYalLAZQ7ZbOPeVkJ8ePao0eLAgEC
-----END DH PARAMETERS-----
  _end_of_pem_

  TEST_KEY_DH1024.priv_key = OpenSSL::BN.new("48561834C67E65FFD2A9B47F41E5E78FDC95C387428FDB1E4B0188B64D1643C3A8D3455B945B7E8C4D166010C7C2CE23BFB9BEF43D0348FE7FA5284B0225E7FE1537546D114E3D8A4411B9B9351AB451E1A358F50ED61B1F00DA29336EEBBD649980AC86D76AF8BBB065298C2052672EEF3EF13AB47A15275FC2836F3AC74CEA", 16)

  DSA_SIGNATURE_DIGEST = OpenSSL::OPENSSL_VERSION_NUMBER > 0x10000000 ?
                         OpenSSL::Digest::SHA1 :
                         OpenSSL::Digest::DSS1

  module_function

  def issue_cert(dn, key, serial, not_before, not_after, extensions,
                 issuer, issuer_key, digest)
    cert = OpenSSL::X509::Certificate.new
    issuer = cert unless issuer
    issuer_key = key unless issuer_key
    cert.version = 2
    cert.serial = serial
    cert.subject = dn
    cert.issuer = issuer.subject
    cert.public_key = key.public_key
    cert.not_before = not_before
    cert.not_after = not_after
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = issuer
    extensions.each{|oid, value, critical|
      cert.add_extension(ef.create_extension(oid, value, critical))
    }
    cert.sign(issuer_key, digest)
    cert
  end

  def issue_crl(revoke_info, serial, lastup, nextup, extensions,
                issuer, issuer_key, digest)
    crl = OpenSSL::X509::CRL.new
    crl.issuer = issuer.subject
    crl.version = 1
    crl.last_update = lastup
    crl.next_update = nextup
    revoke_info.each{|rserial, time, reason_code|
      revoked = OpenSSL::X509::Revoked.new
      revoked.serial = rserial
      revoked.time = time
      enum = OpenSSL::ASN1::Enumerated(reason_code)
      ext = OpenSSL::X509::Extension.new("CRLReason", enum)
      revoked.add_extension(ext)
      crl.add_revoked(revoked)
    }
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.issuer_certificate = issuer
    ef.crl = crl
    crlnum = OpenSSL::ASN1::Integer(serial)
    crl.add_extension(OpenSSL::X509::Extension.new("crlNumber", crlnum))
    extensions.each{|oid, value, critical|
      crl.add_extension(ef.create_extension(oid, value, critical))
    }
    crl.sign(issuer_key, digest)
    crl
  end

  def get_subject_key_id(cert)
    asn1_cert = OpenSSL::ASN1.decode(cert)
    tbscert   = asn1_cert.value[0]
    pkinfo    = tbscert.value[6]
    publickey = pkinfo.value[1]
    pkvalue   = publickey.value
    OpenSSL::Digest::SHA1.hexdigest(pkvalue).scan(/../).join(":").upcase
  end

  def silent
    begin
      back, $VERBOSE = $VERBOSE, nil
      yield
    ensure
      $VERBOSE = back
    end
  end

  class OpenSSL::SSLTestCase < Test::Unit::TestCase
    RUBY = EnvUtil.rubybin
    ITERATIONS = ($0 == __FILE__) ? 100 : 10

    def setup
      @ca_key  = OpenSSL::TestUtils::TEST_KEY_RSA2048
      @svr_key = OpenSSL::TestUtils::TEST_KEY_RSA1024
      @cli_key = OpenSSL::TestUtils::TEST_KEY_DSA256
      @ca  = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=CA")
      @svr = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=localhost")
      @cli = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=localhost")
      now = Time.at(Time.now.to_i)
      ca_exts = [
        ["basicConstraints","CA:TRUE",true],
        ["keyUsage","cRLSign,keyCertSign",true],
      ]
      ee_exts = [
        ["keyUsage","keyEncipherment,digitalSignature",true],
      ]
      @ca_cert  = issue_cert(@ca, @ca_key, 1, now, now+3600, ca_exts, nil, nil, OpenSSL::Digest::SHA1.new)
      @svr_cert = issue_cert(@svr, @svr_key, 2, now, now+1800, ee_exts, @ca_cert, @ca_key, OpenSSL::Digest::SHA1.new)
      @cli_cert = issue_cert(@cli, @cli_key, 3, now, now+1800, ee_exts, @ca_cert, @ca_key, OpenSSL::Digest::SHA1.new)
      @server = nil
    end

    def teardown
    end

    def issue_cert(*arg)
      OpenSSL::TestUtils.issue_cert(*arg)
    end

    def issue_crl(*arg)
      OpenSSL::TestUtils.issue_crl(*arg)
    end

    def readwrite_loop(ctx, ssl)
      while line = ssl.gets
        if line =~ /^STARTTLS$/
          ssl.accept
          next
        end
        ssl.write(line)
      end
    rescue OpenSSL::SSL::SSLError
    rescue IOError
    ensure
      ssl.close rescue nil
    end

    def server_loop(ctx, ssls, stop_pipe_r, ignore_listener_error, server_proc, threads)
      loop do
        ssl = nil
        begin
          readable, = IO.select([ssls, stop_pipe_r])
          if readable.include? stop_pipe_r
            return
          end
          ssl = ssls.accept
        rescue OpenSSL::SSL::SSLError
          if ignore_listener_error
            retry
          else
            raise
          end
        end

        th = Thread.start do
          server_proc.call(ctx, ssl)
        end
        threads << th
      end
    rescue Errno::EBADF, IOError, Errno::EINVAL, Errno::ECONNABORTED, Errno::ENOTSOCK, Errno::ECONNRESET
      if !ignore_listener_error
        raise
      end
    end

    def start_server(verify_mode, start_immediately, args = {}, &block)
      IO.pipe {|stop_pipe_r, stop_pipe_w|
        ctx_proc = args[:ctx_proc]
        server_proc = args[:server_proc]
        ignore_listener_error = args.fetch(:ignore_listener_error, false)
        use_anon_cipher = args.fetch(:use_anon_cipher, false)
        server_proc ||= method(:readwrite_loop)

        store = OpenSSL::X509::Store.new
        store.add_cert(@ca_cert)
        store.purpose = OpenSSL::X509::PURPOSE_SSL_CLIENT
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.ciphers = "ADH-AES256-GCM-SHA384" if use_anon_cipher
        ctx.cert_store = store
        #ctx.extra_chain_cert = [ ca_cert ]
        ctx.cert = @svr_cert
        ctx.key = @svr_key
        ctx.tmp_dh_callback = proc { OpenSSL::TestUtils::TEST_KEY_DH1024 }
        ctx.verify_mode = verify_mode
        ctx_proc.call(ctx) if ctx_proc

        Socket.do_not_reverse_lookup = true
        tcps = nil
        tcps = TCPServer.new("127.0.0.1", 0)
        port = tcps.connect_address.ip_port

        ssls = OpenSSL::SSL::SSLServer.new(tcps, ctx)
        ssls.start_immediately = start_immediately

        threads = []
        begin
          server = Thread.new do
            begin
              server_loop(ctx, ssls, stop_pipe_r, ignore_listener_error, server_proc, threads)
            ensure
              tcps.close
            end
          end
          threads.unshift server

          $stderr.printf("SSL server started: pid=%d port=%d\n", $$, port) if $DEBUG

          client = Thread.new do
            begin
              block.call(server, port.to_i)
            ensure
              stop_pipe_w.close
            end
          end
          threads.unshift client
        ensure
          assert_join_threads(threads)
        end
      }
    end

    def starttls(ssl)
      ssl.puts("STARTTLS")
      sleep 1   # When this line is eliminated, process on Cygwin blocks
                # forever at ssl.connect. But I don't know why it does.
      ssl.connect
    end
  end

end if defined?(OpenSSL::OPENSSL_LIBRARY_VERSION) and
  /\AOpenSSL +0\./ !~ OpenSSL::OPENSSL_LIBRARY_VERSION
