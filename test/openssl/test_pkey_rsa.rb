# frozen_string_literal: false
require_relative "utils"

if defined?(OpenSSL)

class OpenSSL::TestPKeyRSA < OpenSSL::PKeyTestCase
  def test_padding
    key = OpenSSL::PKey::RSA.new(512, 3)

    # Need right size for raw mode
    plain0 = "x" * (512/8)
    cipher = key.private_encrypt(plain0, OpenSSL::PKey::RSA::NO_PADDING)
    plain1 = key.public_decrypt(cipher, OpenSSL::PKey::RSA::NO_PADDING)
    assert_equal(plain0, plain1)

    # Need smaller size for pkcs1 mode
    plain0 = "x" * (512/8 - 11)
    cipher1 = key.private_encrypt(plain0, OpenSSL::PKey::RSA::PKCS1_PADDING)
    plain1 = key.public_decrypt(cipher1, OpenSSL::PKey::RSA::PKCS1_PADDING)
    assert_equal(plain0, plain1)

    cipherdef = key.private_encrypt(plain0) # PKCS1_PADDING is default
    plain1 = key.public_decrypt(cipherdef)
    assert_equal(plain0, plain1)
    assert_equal(cipher1, cipherdef)

    # Failure cases
    assert_raise(ArgumentError){ key.private_encrypt() }
    assert_raise(ArgumentError){ key.private_encrypt("hi", 1, nil) }
    assert_raise(OpenSSL::PKey::RSAError){ key.private_encrypt(plain0, 666) }
  end

  def test_private
    key = OpenSSL::PKey::RSA.new(512, 3)
    assert(key.private?)
    key2 = OpenSSL::PKey::RSA.new(key.to_der)
    assert(key2.private?)
    key3 = key.public_key
    assert(!key3.private?)
    key4 = OpenSSL::PKey::RSA.new(key3.to_der)
    assert(!key4.private?)
  end

  def test_new
    key = OpenSSL::PKey::RSA.new 512
    pem  = key.public_key.to_pem
    OpenSSL::PKey::RSA.new pem
    assert_equal([], OpenSSL.errors)
  end

  def test_new_exponent_default
    assert_equal(65537, OpenSSL::PKey::RSA.new(512).e)
  end

  def test_new_with_exponent
    1.upto(30) do |idx|
      e = (2 ** idx) + 1
      key = OpenSSL::PKey::RSA.new(512, e)
      assert_equal(e, key.e)
    end
  end

  def test_new_break
    assert_nil(OpenSSL::PKey::RSA.new(1024) { break })
    assert_raise(RuntimeError) do
      OpenSSL::PKey::RSA.new(1024) { raise }
    end
  end

  def test_sign_verify
    rsa1024 = Fixtures.pkey("rsa1024")
    data = "Sign me!"
    signature = rsa1024.sign("SHA1", data)
    assert_equal true, rsa1024.verify("SHA1", signature, data)

    signature0 = (<<~'end;').unpack("m")[0]
      oLCgbprPvfhM4pjFQiDTFeWI9Sk+Og7Nh9TmIZ/xSxf2CGXQrptlwo7NQ28+
      WA6YQo8jPH4hSuyWIM4Gz4qRYiYRkl5TDMUYob94zm8Si1HxEiS9354tzvqS
      zS8MLW2BtNPuTubMxTItHGTnOzo9sUg0LAHVFt8kHG2NfKAw/gQ=
    end;
    assert_equal true, rsa1024.verify("SHA256", signature0, data)
    signature1 = signature0.succ
    assert_equal false, rsa1024.verify("SHA256", signature1, data)
  end

  def test_digest_state_irrelevant_sign
    key = Fixtures.pkey("rsa1024")
    digest1 = OpenSSL::Digest::SHA1.new
    digest2 = OpenSSL::Digest::SHA1.new
    data = 'Sign me!'
    digest1 << 'Change state of digest1'
    sig1 = key.sign(digest1, data)
    sig2 = key.sign(digest2, data)
    assert_equal(sig1, sig2)
  end

  def test_digest_state_irrelevant_verify
    key = Fixtures.pkey("rsa1024")
    digest1 = OpenSSL::Digest::SHA1.new
    digest2 = OpenSSL::Digest::SHA1.new
    data = 'Sign me!'
    sig = key.sign(digest1, data)
    digest1.reset
    digest1 << 'Change state of digest1'
    assert(key.verify(digest1, sig, data))
    assert(key.verify(digest2, sig, data))
  end

  def test_verify_empty_rsa
    rsa = OpenSSL::PKey::RSA.new
    assert_raise(OpenSSL::PKey::PKeyError, "[Bug #12783]") {
      rsa.verify("SHA1", "a", "b")
    }
  end

  def test_sign_verify_pss
    key = Fixtures.pkey("rsa1024")
    data = "Sign me!"
    invalid_data = "Sign me?"

    signature = key.sign_pss("SHA256", data, salt_length: 20, mgf1_hash: "SHA1")
    assert_equal 128, signature.bytesize
    assert_equal true,
      key.verify_pss("SHA256", signature, data, salt_length: 20, mgf1_hash: "SHA1")
    assert_equal true,
      key.verify_pss("SHA256", signature, data, salt_length: :auto, mgf1_hash: "SHA1")
    assert_equal false,
      key.verify_pss("SHA256", signature, invalid_data, salt_length: 20, mgf1_hash: "SHA1")

    signature = key.sign_pss("SHA256", data, salt_length: :digest, mgf1_hash: "SHA1")
    assert_equal true,
      key.verify_pss("SHA256", signature, data, salt_length: 32, mgf1_hash: "SHA1")
    assert_equal true,
      key.verify_pss("SHA256", signature, data, salt_length: :auto, mgf1_hash: "SHA1")
    assert_equal false,
      key.verify_pss("SHA256", signature, data, salt_length: 20, mgf1_hash: "SHA1")

    signature = key.sign_pss("SHA256", data, salt_length: :max, mgf1_hash: "SHA1")
    assert_equal true,
      key.verify_pss("SHA256", signature, data, salt_length: 94, mgf1_hash: "SHA1")
    assert_equal true,
      key.verify_pss("SHA256", signature, data, salt_length: :auto, mgf1_hash: "SHA1")

    assert_raise(OpenSSL::PKey::RSAError) {
      key.sign_pss("SHA256", data, salt_length: 95, mgf1_hash: "SHA1")
    }
  end

  def test_RSAPrivateKey
    rsa1024 = Fixtures.pkey("rsa1024")
    asn1 = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Integer(0),
      OpenSSL::ASN1::Integer(rsa1024.n),
      OpenSSL::ASN1::Integer(rsa1024.e),
      OpenSSL::ASN1::Integer(rsa1024.d),
      OpenSSL::ASN1::Integer(rsa1024.p),
      OpenSSL::ASN1::Integer(rsa1024.q),
      OpenSSL::ASN1::Integer(rsa1024.dmp1),
      OpenSSL::ASN1::Integer(rsa1024.dmq1),
      OpenSSL::ASN1::Integer(rsa1024.iqmp)
    ])
    key = OpenSSL::PKey::RSA.new(asn1.to_der)
    assert_predicate key, :private?
    assert_same_rsa rsa1024, key

    pem = <<~EOF
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
    EOF
    key = OpenSSL::PKey::RSA.new(pem)
    assert_same_rsa rsa1024, key

    assert_equal asn1.to_der, rsa1024.to_der
    assert_equal pem, rsa1024.export
  end

  def test_RSAPrivateKey_encrypted
    rsa1024 = Fixtures.pkey("rsa1024")
    # key = abcdef
    pem = <<~EOF
    -----BEGIN RSA PRIVATE KEY-----
    Proc-Type: 4,ENCRYPTED
    DEK-Info: AES-128-CBC,733F5302505B34701FC41F5C0746E4C0

    zgJniZZQfvv8TFx3LzV6zhAQVayvQVZlAYqFq2yWbbxzF7C+IBhKQle9IhUQ9j/y
    /jkvol550LS8vZ7TX5WxyDLe12cdqzEvpR6jf3NbxiNysOCxwG4ErhaZGP+krcoB
    ObuL0nvls/+3myy5reKEyy22+0GvTDjaChfr+FwJjXMG+IBCLscYdgZC1LQL6oAn
    9xY5DH3W7BW4wR5ttxvtN32TkfVQh8xi3jrLrduUh+hV8DTiAiLIhv0Vykwhep2p
    WZA+7qbrYaYM8GLLgLrb6LfBoxeNxAEKiTpl1quFkm+Hk1dKq0EhVnxHf92x0zVF
    jRGZxAMNcrlCoE4f5XK45epVZSZvihdo1k73GPbp84aZ5P/xlO4OwZ3i4uCQXynl
    jE9c+I+4rRWKyPz9gkkqo0+teJL8ifeKt/3ab6FcdA0aArynqmsKJMktxmNu83We
    YVGEHZPeOlyOQqPvZqWsLnXQUfg54OkbuV4/4mWSIzxFXdFy/AekSeJugpswMXqn
    oNck4qySNyfnlyelppXyWWwDfVus9CVAGZmJQaJExHMT/rQFRVchlmY0Ddr5O264
    gcjv90o1NBOc2fNcqjivuoX7ROqys4K/YdNQ1HhQ7usJghADNOtuLI8ZqMh9akXD
    Eqp6Ne97wq1NiJj0nt3SJlzTnOyTjzrTe0Y+atPkVKp7SsjkATMI9JdhXwGhWd7a
    qFVl0owZiDasgEhyG2K5L6r+yaJLYkPVXZYC/wtWC3NEchnDWZGQcXzB4xROCQkD
    OlWNYDkPiZioeFkA3/fTMvG4moB2Pp9Q4GU5fJ6k43Ccu1up8dX/LumZb4ecg5/x
    -----END RSA PRIVATE KEY-----
    EOF
    key = OpenSSL::PKey::RSA.new(pem, "abcdef")
    assert_same_rsa rsa1024, key
    key = OpenSSL::PKey::RSA.new(pem) { "abcdef" }
    assert_same_rsa rsa1024, key

    cipher = OpenSSL::Cipher.new("aes-128-cbc")
    exported = rsa1024.to_pem(cipher, "abcdef\0\1")
    assert_same_rsa rsa1024, OpenSSL::PKey::RSA.new(exported, "abcdef\0\1")
    assert_raise(OpenSSL::PKey::RSAError) {
      OpenSSL::PKey::RSA.new(exported, "abcdef")
    }
  end

  def test_RSAPublicKey
    rsa1024 = Fixtures.pkey("rsa1024")
    asn1 = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Integer(rsa1024.n),
      OpenSSL::ASN1::Integer(rsa1024.e)
    ])
    key = OpenSSL::PKey::RSA.new(asn1.to_der)
    assert_not_predicate key, :private?
    assert_same_rsa dup_public(rsa1024), key

    pem = <<~EOF
    -----BEGIN RSA PUBLIC KEY-----
    MIGJAoGBAMvCxLDUQKc+1P4+Q6AeFwYDvWfALb+cvzlUEadGoPE6qNWHsLFoo8RF
    geyTgE8KQTduu1OE9Zz2SMcRBDu5/1jWtsLPSVrI2ofLLBARUsWanVyki39DeB4u
    /xkP2mKGjAokPIwOI3oCthSZlzO9bj3voxTf6XngTqUX8l8URTmHAgMBAAE=
    -----END RSA PUBLIC KEY-----
    EOF
    key = OpenSSL::PKey::RSA.new(pem)
    assert_same_rsa dup_public(rsa1024), key
  end

  def test_PUBKEY
    rsa1024 = Fixtures.pkey("rsa1024")
    asn1 = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Sequence([
        OpenSSL::ASN1::ObjectId("rsaEncryption"),
        OpenSSL::ASN1::Null(nil)
      ]),
      OpenSSL::ASN1::BitString(
        OpenSSL::ASN1::Sequence([
          OpenSSL::ASN1::Integer(rsa1024.n),
          OpenSSL::ASN1::Integer(rsa1024.e)
        ]).to_der
      )
    ])
    key = OpenSSL::PKey::RSA.new(asn1.to_der)
    assert_not_predicate key, :private?
    assert_same_rsa dup_public(rsa1024), key

    pem = <<~EOF
    -----BEGIN PUBLIC KEY-----
    MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDLwsSw1ECnPtT+PkOgHhcGA71n
    wC2/nL85VBGnRqDxOqjVh7CxaKPERYHsk4BPCkE3brtThPWc9kjHEQQ7uf9Y1rbC
    z0layNqHyywQEVLFmp1cpIt/Q3geLv8ZD9pihowKJDyMDiN6ArYUmZczvW4976MU
    3+l54E6lF/JfFEU5hwIDAQAB
    -----END PUBLIC KEY-----
    EOF
    key = OpenSSL::PKey::RSA.new(pem)
    assert_same_rsa dup_public(rsa1024), key

    assert_equal asn1.to_der, dup_public(rsa1024).to_der
    assert_equal pem, dup_public(rsa1024).export
  end

  def test_pem_passwd
    key = Fixtures.pkey("rsa1024")
    pem3c = key.to_pem("aes-128-cbc", "key")
    assert_match (/ENCRYPTED/), pem3c
    assert_equal key.to_der, OpenSSL::PKey.read(pem3c, "key").to_der
    assert_equal key.to_der, OpenSSL::PKey.read(pem3c) { "key" }.to_der
    assert_raise(OpenSSL::PKey::PKeyError) {
      OpenSSL::PKey.read(pem3c) { nil }
    }
  end

  def test_dup
    key = OpenSSL::PKey::RSA.generate(256, 17)
    key2 = key.dup
    assert_equal key.params, key2.params
    key2.set_key(key2.n, 3, key2.d)
    assert_not_equal key.params, key2.params
  end

  private
  def assert_same_rsa(expected, key)
    check_component(expected, key, [:n, :e, :d, :p, :q, :dmp1, :dmq1, :iqmp])
  end
end

end
