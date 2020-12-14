# frozen_string_literal: true
require_relative "utils"

if defined?(OpenSSL)

class OpenSSL::TestX509Store < OpenSSL::TestCase
  def test_store_new
    # v2.3.0 emits explicit warning
    assert_warning(/new does not take any arguments/) {
      OpenSSL::X509::Store.new(123)
    }
  end

  def test_add_file_path
    ca_exts = [
      ["basicConstraints", "CA:TRUE", true],
      ["keyUsage", "cRLSign,keyCertSign", true],
    ]
    cert1_subj = OpenSSL::X509::Name.parse_rfc2253("CN=Cert 1")
    cert1_key = Fixtures.pkey("rsa-1")
    cert1 = issue_cert(cert1_subj, cert1_key, 1, ca_exts, nil, nil)
    cert2_subj = OpenSSL::X509::Name.parse_rfc2253("CN=Cert 2")
    cert2_key = Fixtures.pkey("rsa-2")
    cert2 = issue_cert(cert2_subj, cert2_key, 1, ca_exts, nil, nil)

    # X509::Store#add_file reads concatenated PEM file
    tmpfile = Tempfile.open { |f| f << cert1.to_pem << cert2.to_pem; f }
    store = OpenSSL::X509::Store.new
    assert_equal false, store.verify(cert1)
    assert_equal false, store.verify(cert2)
    store.add_file(tmpfile.path)
    assert_equal true, store.verify(cert1)
    assert_equal true, store.verify(cert2)

    unless libressl?(3, 2, 2)
      # X509::Store#add_path
      Dir.mktmpdir do |dir|
        hash1 = "%08x.%d" % [cert1_subj.hash, 0]
        File.write(File.join(dir, hash1), cert1.to_pem)
        store = OpenSSL::X509::Store.new
        store.add_path(dir)

        assert_equal true, store.verify(cert1)
        assert_equal false, store.verify(cert2)
      end
    end

    # OpenSSL < 1.1.1 leaks an error on a duplicate certificate
    assert_nothing_raised { store.add_file(tmpfile.path) }
    assert_equal [], OpenSSL.errors

    # Non-String is given
    assert_raise(TypeError) { store.add_file(nil) }
  ensure
    tmpfile and tmpfile.close!
  end

  def test_verify_simple
    ca_exts = [
      ["basicConstraints", "CA:TRUE", true],
      ["keyUsage", "cRLSign,keyCertSign", true],
    ]
    ca1 = OpenSSL::X509::Name.parse_rfc2253("CN=Root CA")
    ca1_key = Fixtures.pkey("rsa-1")
    ca1_cert = issue_cert(ca1, ca1_key, 1, ca_exts, nil, nil)
    ca2 = OpenSSL::X509::Name.parse_rfc2253("CN=Intermediate CA")
    ca2_key = Fixtures.pkey("rsa-2")
    ca2_cert = issue_cert(ca2, ca2_key, 2, ca_exts, ca1_cert, ca1_key)

    ee_exts = [
      ["keyUsage", "keyEncipherment,digitalSignature", true],
    ]
    ee1 = OpenSSL::X509::Name.parse_rfc2253("CN=EE 1")
    ee1_key = Fixtures.pkey("rsa-3")
    ee1_cert = issue_cert(ee1, ee1_key, 10, ee_exts, ca2_cert, ca2_key)

    # Nothing trusted
    store = OpenSSL::X509::Store.new
    assert_equal(false, store.verify(ee1_cert, [ca2_cert, ca1_cert]))
    assert_include([OpenSSL::X509::V_ERR_SELF_SIGNED_CERT_IN_CHAIN, OpenSSL::X509::V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY], store.error)
    assert_match(/self.signed|unable to get local issuer certificate/i, store.error_string)

    # CA1 trusted, CA2 missing
    store = OpenSSL::X509::Store.new
    store.add_cert(ca1_cert)
    assert_equal(false, store.verify(ee1_cert))
    assert_equal(OpenSSL::X509::V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY, store.error)

    # CA1 trusted, CA2 supplied
    store = OpenSSL::X509::Store.new
    store.add_cert(ca1_cert)
    assert_equal(true, store.verify(ee1_cert, [ca2_cert]))
    assert_match(/ok/i, store.error_string)
    assert_equal(OpenSSL::X509::V_OK, store.error)
    assert_equal([ee1_cert, ca2_cert, ca1_cert], store.chain)
  end

  def test_verify_callback
    ca_exts = [
      ["basicConstraints", "CA:TRUE", true],
      ["keyUsage", "cRLSign,keyCertSign", true],
    ]
    ca1 = OpenSSL::X509::Name.parse_rfc2253("CN=Root CA")
    ca1_key = Fixtures.pkey("rsa-1")
    ca1_cert = issue_cert(ca1, ca1_key, 1, ca_exts, nil, nil)
    ca2 = OpenSSL::X509::Name.parse_rfc2253("CN=Intermediate CA")
    ca2_key = Fixtures.pkey("rsa-2")
    ca2_cert = issue_cert(ca2, ca2_key, 2, ca_exts, ca1_cert, ca1_key)

    ee_exts = [
      ["keyUsage", "keyEncipherment,digitalSignature", true],
    ]
    ee1 = OpenSSL::X509::Name.parse_rfc2253("CN=EE 1")
    ee1_key = Fixtures.pkey("rsa-3")
    ee1_cert = issue_cert(ee1, ee1_key, 10, ee_exts, ca2_cert, ca2_key)

    # verify_callback on X509::Store is called with proper arguments
    cb_calls = []
    store = OpenSSL::X509::Store.new
    store.verify_callback = -> (preverify_ok, sctx) {
      cb_calls << [preverify_ok, sctx.current_cert]
      preverify_ok
    }
    store.add_cert(ca1_cert)
    assert_equal(true, store.verify(ee1_cert, [ca2_cert]))
    assert_include([2, 3, 4, 5], cb_calls.size)
    cb_calls.each do |pre_ok, cert|
      assert_equal(true, pre_ok)
      assert_include([ca1_cert, ca2_cert, ee1_cert], cert)
    end

    # verify_callback can change verification result
    store = OpenSSL::X509::Store.new
    store.verify_callback = -> (preverify_ok, sctx) {
      next preverify_ok if sctx.current_cert != ee1_cert
      sctx.error = OpenSSL::X509::V_ERR_APPLICATION_VERIFICATION
      false
    }
    store.add_cert(ca1_cert)
    assert_equal(false, store.verify(ee1_cert, [ca2_cert]))
    assert_equal(OpenSSL::X509::V_ERR_APPLICATION_VERIFICATION, store.error)

    # Exception raised by verify_callback is currently suppressed, and is
    # treated as a non-truthy return (with warning)
    store = OpenSSL::X509::Store.new
    store.verify_callback = -> (preverify_ok, sctx) {
      raise "suppressed"
    }
    store.add_cert(ca1_cert)
    assert_warning(/exception in verify_callback/) {
      assert_equal(false, store.verify(ee1_cert, [ca2_cert]))
    }

    # The block given to X509::Store#verify replaces it
    called = nil
    store = OpenSSL::X509::Store.new
    store.verify_callback = -> (preverify_ok, sctx) { called = :store; preverify_ok }
    store.add_cert(ca1_cert)
    blk = proc { |preverify_ok, sctx| called = :block; preverify_ok }
    assert_equal(true, store.verify(ee1_cert, [ca2_cert], &blk))
    assert_equal(:block, called)
  end

  def test_verify_purpose
    ca_exts = [
      ["basicConstraints", "CA:TRUE", true],
      ["keyUsage", "cRLSign,keyCertSign", true],
    ]
    ca1 = OpenSSL::X509::Name.parse_rfc2253("CN=Root CA")
    ca1_key = Fixtures.pkey("rsa-1")
    ca1_cert = issue_cert(ca1, ca1_key, 1, ca_exts, nil, nil)

    ee_exts = [
      ["keyUsage", "keyEncipherment,digitalSignature", true],
    ]
    ee1 = OpenSSL::X509::Name.parse_rfc2253("CN=EE 1")
    ee1_key = Fixtures.pkey("rsa-3")
    ee1_cert = issue_cert(ee1, ee1_key, 10, ee_exts, ca1_cert, ca1_key)

    # Purpose not set
    store = OpenSSL::X509::Store.new
    store.add_cert(ca1_cert)
    assert_equal(true, store.verify(ca1_cert))
    assert_equal(true, store.verify(ee1_cert))

    # Purpose set to X509::PURPOSE_SSL_CLIENT; keyUsage is checked
    store = OpenSSL::X509::Store.new
    store.purpose = OpenSSL::X509::PURPOSE_CRL_SIGN
    store.add_cert(ca1_cert)
    assert_equal(true, store.verify(ca1_cert))
    assert_equal(libressl?(3, 2, 2), store.verify(ee1_cert))
  end

  def test_verify_validity_period
    # Creating test certificates with validity periods:
    #
    #  now-5000                 now-1000    now+1000                  now+5000
    # CA1:|---------------------------------------------------------------|
    # EE1:|---------------------------------------------------------------|
    # EE2:|-------------------------|
    # EE3:                                      |-------------------------|
    now = Time.now
    ca_exts = [
      ["basicConstraints", "CA:TRUE", true],
      ["keyUsage", "cRLSign,keyCertSign", true],
    ]
    ca1 = OpenSSL::X509::Name.parse_rfc2253("CN=Root CA")
    ca1_key = Fixtures.pkey("rsa-1")
    ca1_cert = issue_cert(ca1, ca1_key, 1, ca_exts, nil, nil,
                          not_before: now - 5000, not_after: now + 5000)

    ee_exts = [
      ["keyUsage", "keyEncipherment,digitalSignature", true],
    ]
    ee1 = OpenSSL::X509::Name.parse_rfc2253("CN=EE 1")
    ee1_key = Fixtures.pkey("rsa-1")
    ee1_cert = issue_cert(ee1, ee1_key, 11, ee_exts, ca1_cert, ca1_key,
                          not_before: now - 5000, not_after: now + 5000)
    ee2 = OpenSSL::X509::Name.parse_rfc2253("CN=EE 2")
    ee2_key = Fixtures.pkey("rsa-2")
    ee2_cert = issue_cert(ee2, ee2_key, 12, ee_exts, ca1_cert, ca1_key,
                          not_before: now - 5000, not_after: now - 1000)
    ee3 = OpenSSL::X509::Name.parse_rfc2253("CN=EE 3")
    ee3_key = Fixtures.pkey("rsa-3")
    ee3_cert = issue_cert(ee3, ee3_key, 13, ee_exts, ca1_cert, ca1_key,
                          not_before: now + 1000, not_after: now + 5000)

    # Using system time
    store = OpenSSL::X509::Store.new
    store.add_cert(ca1_cert)
    assert_equal(true, store.verify(ee1_cert))
    assert_equal(false, store.verify(ee2_cert))
    assert_equal(OpenSSL::X509::V_ERR_CERT_HAS_EXPIRED, store.error)
    assert_equal(false, store.verify(ee3_cert))
    assert_equal(OpenSSL::X509::V_ERR_CERT_NOT_YET_VALID, store.error)

    # Time set to now-2000; EE2 is still valid
    store = OpenSSL::X509::Store.new
    store.time = now - 2000
    store.add_cert(ca1_cert)
    assert_equal(true, store.verify(ee1_cert))
    assert_equal(true, store.verify(ee2_cert))
    assert_equal(false, store.verify(ee3_cert))
    assert_equal(OpenSSL::X509::V_ERR_CERT_NOT_YET_VALID, store.error)
  end

  def test_verify_with_crl
    ca_exts = [
      ["basicConstraints", "CA:TRUE", true],
      ["keyUsage", "cRLSign,keyCertSign", true],
    ]
    ca1 = OpenSSL::X509::Name.parse_rfc2253("CN=Root CA")
    ca1_key = Fixtures.pkey("rsa-1")
    ca1_cert = issue_cert(ca1, ca1_key, 1, ca_exts, nil, nil)
    ca2 = OpenSSL::X509::Name.parse_rfc2253("CN=Intermediate CA")
    ca2_key = Fixtures.pkey("rsa-2")
    ca2_cert = issue_cert(ca2, ca2_key, 2, ca_exts, ca1_cert, ca1_key)

    ee_exts = [
      ["keyUsage", "keyEncipherment,digitalSignature", true],
    ]
    ee1 = OpenSSL::X509::Name.parse_rfc2253("CN=EE 1")
    ee1_key = Fixtures.pkey("rsa-3")
    ee1_cert = issue_cert(ee1, ee1_key, 10, ee_exts, ca2_cert, ca2_key)
    ee2 = OpenSSL::X509::Name.parse_rfc2253("CN=EE 2")
    ee2_key = Fixtures.pkey("rsa-3")
    ee2_cert = issue_cert(ee2, ee2_key, 20, ee_exts, ca2_cert, ca2_key)

    # OpenSSL uses time(2) while Time.now uses clock_gettime(CLOCK_REALTIME),
    # and there may be difference, so giving 50 seconds margin.
    now = Time.now - 50
    revoke_info = []
    ca1_crl1 = issue_crl(revoke_info, 1, now, now+1800, [], ca1_cert, ca1_key, "sha256")
    revoke_info = [ [2, now, 1], ]
    ca1_crl2 = issue_crl(revoke_info, 2, now, now+1800, [], ca1_cert, ca1_key, "sha256")

    revoke_info = [ [20, now, 1], ]
    ca2_crl1 = issue_crl(revoke_info, 1, now, now+1800, [], ca2_cert, ca2_key, "sha256")
    revoke_info = []
    ca2_crl2 = issue_crl(revoke_info, 2, now-100, now-1, [], ca2_cert, ca2_key, "sha256")

    # CRL check required, but no CRL supplied
    store = OpenSSL::X509::Store.new
    store.flags = OpenSSL::X509::V_FLAG_CRL_CHECK
    store.add_cert(ca1_cert)
    assert_equal(false, store.verify(ca2_cert))
    assert_include([OpenSSL::X509::V_ERR_UNABLE_TO_GET_CRL, OpenSSL::X509::V_ERR_UNSPECIFIED], store.error)

    # Intermediate CA revoked EE2
    store = OpenSSL::X509::Store.new
    store.flags = OpenSSL::X509::V_FLAG_CRL_CHECK
    store.add_cert(ca1_cert)
    store.add_crl(ca1_crl1) # revoke no cert
    store.add_crl(ca2_crl1) # revoke ee2_cert
    assert_equal(true, store.verify(ca2_cert))
    assert_equal(true, store.verify(ee1_cert, [ca2_cert]))
    assert_equal(false, store.verify(ee2_cert, [ca2_cert]))

    # Root CA revoked Intermediate CA; Intermediate CA revoked EE2
    store = OpenSSL::X509::Store.new
    store.flags = OpenSSL::X509::V_FLAG_CRL_CHECK
    store.add_cert(ca1_cert)
    store.add_crl(ca1_crl2) # revoke ca2_cert
    store.add_crl(ca2_crl1) # revoke ee2_cert
    assert_equal(false, store.verify(ca2_cert))
    # Validity of intermediate CAs is not checked by default
    assert_equal(true, store.verify(ee1_cert, [ca2_cert]))
    assert_equal(false, store.verify(ee2_cert, [ca2_cert]))

    # Same as above, but with OpenSSL::X509::V_FLAG_CRL_CHECK_ALL
    store = OpenSSL::X509::Store.new
    store.flags = OpenSSL::X509::V_FLAG_CRL_CHECK|OpenSSL::X509::V_FLAG_CRL_CHECK_ALL
    store.add_cert(ca1_cert)
    store.add_crl(ca1_crl2) # revoke ca2_cert
    store.add_crl(ca2_crl1) # revoke ee2_cert
    assert_equal(false, store.verify(ca2_cert))
    assert_equal(false, store.verify(ee1_cert, [ca2_cert]))
    assert_equal(false, store.verify(ee2_cert, [ca2_cert]))

    # Expired CRL supplied
    store = OpenSSL::X509::Store.new
    store.flags = OpenSSL::X509::V_FLAG_CRL_CHECK|OpenSSL::X509::V_FLAG_CRL_CHECK_ALL
    store.add_cert(ca1_cert)
    store.add_cert(ca2_cert)
    store.add_crl(ca1_crl1)
    store.add_crl(ca2_crl2) # issued by ca2 but expired
    if libressl?(3, 2, 2)
      assert_equal(false, store.verify(ca2_cert))
      assert_include([OpenSSL::X509::V_ERR_CRL_SIGNATURE_FAILURE, OpenSSL::X509::V_ERR_UNSPECIFIED], store.error)
    else
      assert_equal(true, store.verify(ca2_cert))
    end
    assert_equal(false, store.verify(ee1_cert))
    assert_include([OpenSSL::X509::V_ERR_CRL_HAS_EXPIRED, OpenSSL::X509::V_ERR_UNSPECIFIED], store.error)
    assert_equal(false, store.verify(ee2_cert))
  end

  def test_add_cert_duplicate
    # Up until OpenSSL 1.1.0, X509_STORE_add_{cert,crl}() returned an error
    # if the given certificate is already in the X509_STORE
    return if openssl?(1, 1, 0) || libressl?
    ca1 = OpenSSL::X509::Name.parse_rfc2253("CN=Root CA")
    ca1_key = Fixtures.pkey("rsa-1")
    ca1_cert = issue_cert(ca1, ca1_key, 1, [], nil, nil)
    store = OpenSSL::X509::Store.new
    store.add_cert(ca1_cert)
    assert_raise(OpenSSL::X509::StoreError){
      store.add_cert(ca1_cert)  # add same certificate twice
    }

    now = Time.now
    revoke_info = []
    crl1 = issue_crl(revoke_info, 1, now, now+1800, [],
                     ca1_cert, ca1_key, "sha256")
    revoke_info = [ [2, now, 1], ]
    crl2 = issue_crl(revoke_info, 2, now+1800, now+3600, [],
                     ca1_cert, ca1_key, "sha256")
    store.add_crl(crl1)
    assert_raise(OpenSSL::X509::StoreError){
      store.add_crl(crl2) # add CRL issued by same CA twice.
    }
  end

  def test_dup
    store = OpenSSL::X509::Store.new
    assert_raise(NoMethodError) { store.dup }
    ctx = OpenSSL::X509::StoreContext.new(store)
    assert_raise(NoMethodError) { ctx.dup }
  end

  def test_ctx_cleanup
    # Deprecated in Ruby 1.9.3
    cert  = OpenSSL::X509::Certificate.new
    store = OpenSSL::X509::Store.new
    ctx   = OpenSSL::X509::StoreContext.new(store, cert, [])
    assert_warning(/cleanup/) { ctx.cleanup }
  end
end

end
