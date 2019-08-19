# frozen_string_literal: false
require_relative 'utils'

if defined?(OpenSSL)

class OpenSSL::TestKDF < OpenSSL::TestCase
  def test_pkcs5_pbkdf2_hmac_compatibility
    expected = OpenSSL::KDF.pbkdf2_hmac("password", salt: "salt", iterations: 1, length: 20, hash: "sha1")
    assert_equal(expected, OpenSSL::PKCS5.pbkdf2_hmac("password", "salt", 1, 20, "sha1"))
    assert_equal(expected, OpenSSL::PKCS5.pbkdf2_hmac_sha1("password", "salt", 1, 20))
  end

  def test_pbkdf2_hmac_sha1_rfc6070_c_1_len_20
    p ="password"
    s = "salt"
    c = 1
    dk_len = 20
    raw = %w{ 0c 60 c8 0f 96 1f 0e 71
              f3 a9 b5 24 af 60 12 06
              2f e0 37 a6 }
    expected = [raw.join('')].pack('H*')
    value = OpenSSL::KDF.pbkdf2_hmac(p, salt: s, iterations: c, length: dk_len, hash: "sha1")
    assert_equal(expected, value)
  end

  def test_pbkdf2_hmac_sha1_rfc6070_c_2_len_20
    p ="password"
    s = "salt"
    c = 2
    dk_len = 20
    raw = %w{ ea 6c 01 4d c7 2d 6f 8c
              cd 1e d9 2a ce 1d 41 f0
              d8 de 89 57 }
    expected = [raw.join('')].pack('H*')
    value = OpenSSL::KDF.pbkdf2_hmac(p, salt: s, iterations: c, length: dk_len, hash: "sha1")
    assert_equal(expected, value)
  end

  def test_pbkdf2_hmac_sha1_rfc6070_c_4096_len_20
    p ="password"
    s = "salt"
    c = 4096
    dk_len = 20
    raw = %w{ 4b 00 79 01 b7 65 48 9a
              be ad 49 d9 26 f7 21 d0
              65 a4 29 c1 }
    expected = [raw.join('')].pack('H*')
    value = OpenSSL::KDF.pbkdf2_hmac(p, salt: s, iterations: c, length: dk_len, hash: "sha1")
    assert_equal(expected, value)
  end

# takes too long!
#  def test_pbkdf2_hmac_sha1_rfc6070_c_16777216_len_20
#    p ="password"
#    s = "salt"
#    c = 16777216
#    dk_len = 20
#    raw = %w{ ee fe 3d 61 cd 4d a4 e4
#              e9 94 5b 3d 6b a2 15 8c
#              26 34 e9 84 }
#    expected = [raw.join('')].pack('H*')
#    value = OpenSSL::KDF.pbkdf2_hmac(p, salt: s, iterations: c, length: dk_len, hash: "sha1")
#    assert_equal(expected, value)
#  end

  def test_pbkdf2_hmac_sha1_rfc6070_c_4096_len_25
    p ="passwordPASSWORDpassword"
    s = "saltSALTsaltSALTsaltSALTsaltSALTsalt"
    c = 4096
    dk_len = 25

    raw = %w{ 3d 2e ec 4f e4 1c 84 9b
              80 c8 d8 36 62 c0 e4 4a
              8b 29 1a 96 4c f2 f0 70
              38 }
    expected = [raw.join('')].pack('H*')
    value = OpenSSL::KDF.pbkdf2_hmac(p, salt: s, iterations: c, length: dk_len, hash: "sha1")
    assert_equal(expected, value)
  end

  def test_pbkdf2_hmac_sha1_rfc6070_c_4096_len_16
    p ="pass\0word"
    s = "sa\0lt"
    c = 4096
    dk_len = 16
    raw = %w{ 56 fa 6a a7 55 48 09 9d
              cc 37 d7 f0 34 25 e0 c3 }
    expected = [raw.join('')].pack('H*')
    value = OpenSSL::KDF.pbkdf2_hmac(p, salt: s, iterations: c, length: dk_len, hash: "sha1")
    assert_equal(expected, value)
  end

  def test_pbkdf2_hmac_sha256_c_20000_len_32
    #unfortunately no official test vectors available yet for SHA-2
    p ="password"
    s = OpenSSL::Random.random_bytes(16)
    c = 20000
    dk_len = 32
    value1 = OpenSSL::KDF.pbkdf2_hmac(p, salt: s, iterations: c, length: dk_len, hash: "sha256")
    value2 = OpenSSL::KDF.pbkdf2_hmac(p, salt: s, iterations: c, length: dk_len, hash: "sha256")
    assert_equal(value1, value2)
  end

  def test_scrypt_rfc7914_first
    pend "scrypt is not implemented" unless OpenSSL::KDF.respond_to?(:scrypt) # OpenSSL >= 1.1.0
    pass = ""
    salt = ""
    n = 16
    r = 1
    p = 1
    dklen = 64
    expected = B(%w{ 77 d6 57 62 38 65 7b 20 3b 19 ca 42 c1 8a 04 97
                     f1 6b 48 44 e3 07 4a e8 df df fa 3f ed e2 14 42
                     fc d0 06 9d ed 09 48 f8 32 6a 75 3a 0f c8 1f 17
                     e8 d3 e0 fb 2e 0d 36 28 cf 35 e2 0c 38 d1 89 06 })
    assert_equal(expected, OpenSSL::KDF.scrypt(pass, salt: salt, N: n, r: r, p: p, length: dklen))
  end

  def test_scrypt_rfc7914_second
    pend "scrypt is not implemented" unless OpenSSL::KDF.respond_to?(:scrypt) # OpenSSL >= 1.1.0
    pass = "password"
    salt = "NaCl"
    n = 1024
    r = 8
    p = 16
    dklen = 64
    expected = B(%w{ fd ba be 1c 9d 34 72 00 78 56 e7 19 0d 01 e9 fe
                     7c 6a d7 cb c8 23 78 30 e7 73 76 63 4b 37 31 62
                     2e af 30 d9 2e 22 a3 88 6f f1 09 27 9d 98 30 da
                     c7 27 af b9 4a 83 ee 6d 83 60 cb df a2 cc 06 40 })
    assert_equal(expected, OpenSSL::KDF.scrypt(pass, salt: salt, N: n, r: r, p: p, length: dklen))
  end

  def test_hkdf_rfc5869_test_case_1
    pend "HKDF is not implemented" unless OpenSSL::KDF.respond_to?(:hkdf) # OpenSSL >= 1.1.0
    hash = "sha256"
    ikm = B("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b")
    salt = B("000102030405060708090a0b0c")
    info = B("f0f1f2f3f4f5f6f7f8f9")
    l = 42

    okm = B("3cb25f25faacd57a90434f64d0362f2a" \
            "2d2d0a90cf1a5a4c5db02d56ecc4c5bf" \
            "34007208d5b887185865")
    assert_equal(okm, OpenSSL::KDF.hkdf(ikm, salt: salt, info: info, length: l, hash: hash))
  end

  def test_hkdf_rfc5869_test_case_3
    pend "HKDF is not implemented" unless OpenSSL::KDF.respond_to?(:hkdf) # OpenSSL >= 1.1.0
    hash = "sha256"
    ikm = B("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b")
    salt = B("")
    info = B("")
    l = 42

    okm = B("8da4e775a563c18f715f802a063c5a31" \
            "b8a11f5c5ee1879ec3454e5f3c738d2d" \
            "9d201395faa4b61a96c8")
    assert_equal(okm, OpenSSL::KDF.hkdf(ikm, salt: salt, info: info, length: l, hash: hash))
  end

  def test_hkdf_rfc5869_test_case_4
    pend "HKDF is not implemented" unless OpenSSL::KDF.respond_to?(:hkdf) # OpenSSL >= 1.1.0
    hash = "sha1"
    ikm = B("0b0b0b0b0b0b0b0b0b0b0b")
    salt = B("000102030405060708090a0b0c")
    info = B("f0f1f2f3f4f5f6f7f8f9")
    l = 42

    okm = B("085a01ea1b10f36933068b56efa5ad81" \
            "a4f14b822f5b091568a9cdd4f155fda2" \
            "c22e422478d305f3f896")
    assert_equal(okm, OpenSSL::KDF.hkdf(ikm, salt: salt, info: info, length: l, hash: hash))
  end

  private

  def B(ary)
    [Array(ary).join].pack("H*")
  end
end

end
