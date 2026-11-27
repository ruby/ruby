# frozen_string_literal: true
require_relative 'utils'

if defined?(OpenSSL)

class OpenSSL::TestKDF < OpenSSL::TestCase
  def test_pkcs5_pbkdf2_hmac_compatibility
    # PBKDF2 salt >= 16 bytes (128 bits) and iterations >= 1000 are required in
    # FIPS.
    # SP 800-132.
    # https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-132.pdf
    # * 5.1 The Salt (S)
    # * 5.2 The Iteration Count (C)
    # https://github.com/openssl/openssl/blob/71943544885ff364a10bcc5ffc62d0e651c9a021/providers/implementations/kdfs/pbkdf2.c#L235-L240
    # https://github.com/openssl/openssl/blob/71943544885ff364a10bcc5ffc62d0e651c9a021/providers/implementations/kdfs/pbkdf2.c#L247-L252
    # Use the same parameters with test_pbkdf2_hmac_sha1_rfc6070_c_4096_len_25.
    expected = OpenSSL::KDF.pbkdf2_hmac("passwordPASSWORDpassword",
                                        salt: "saltSALTsaltSALTsaltSALTsaltSALTsalt",
                                        iterations: 4096,
                                        length: 25,
                                        hash: "sha1")
    assert_equal(expected, OpenSSL::PKCS5.pbkdf2_hmac("passwordPASSWORDpassword",
                                                      "saltSALTsaltSALTsaltSALTsaltSALTsalt",
                                                      4096,
                                                      25,
                                                      "sha1"))
    assert_equal(expected, OpenSSL::PKCS5.pbkdf2_hmac_sha1("passwordPASSWORDpassword",
                                                           "saltSALTsaltSALTsaltSALTsaltSALTsalt",
                                                           4096,
                                                           25))
  end

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
    # scrypt is not available in FIPS.
    # EVP_KDF_fetch(ctx, OSSL_KDF_NAME_SCRYPT, propq) returns NULL in FIPS.
    # https://github.com/openssl/openssl/blob/71943544885ff364a10bcc5ffc62d0e651c9a021/crypto/evp/pbe_scrypt.c#L67-L71
    omit_on_fips

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
    # scrypt is not available in FIPS.
    omit_on_fips

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

  # https://www.rfc-editor.org/rfc/rfc5869#appendix-A.1
  def test_hkdf_rfc5869_test_case_1
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

  # https://www.rfc-editor.org/rfc/rfc5869#appendix-A.3
  def test_hkdf_rfc5869_test_case_3
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

  # https://www.rfc-editor.org/rfc/rfc5869#appendix-A.5
  def test_hkdf_rfc5869_test_case_5
    hash = "sha1"
    ikm = B("000102030405060708090a0b0c0d0e0f" \
            "101112131415161718191a1b1c1d1e1f" \
            "202122232425262728292a2b2c2d2e2f" \
            "303132333435363738393a3b3c3d3e3f" \
            "404142434445464748494a4b4c4d4e4f")
    salt = B("606162636465666768696a6b6c6d6e6f" \
             "707172737475767778797a7b7c7d7e7f" \
             "808182838485868788898a8b8c8d8e8f" \
             "909192939495969798999a9b9c9d9e9f" \
             "a0a1a2a3a4a5a6a7a8a9aaabacadaeaf")
    info = B("b0b1b2b3b4b5b6b7b8b9babbbcbdbebf" \
             "c0c1c2c3c4c5c6c7c8c9cacbcccdcecf" \
             "d0d1d2d3d4d5d6d7d8d9dadbdcdddedf" \
             "e0e1e2e3e4e5e6e7e8e9eaebecedeeef" \
             "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
    l = 82

    okm = B("0bd770a74d1160f7c9f12cd5912a06eb" \
            "ff6adcae899d92191fe4305673ba2ffe" \
            "8fa3f1a4e5ad79f3f334b3b202b2173c" \
            "486ea37ce3d397ed034c7f9dfeb15c5e" \
            "927336d0441f4c4300e2cff0d0900b52" \
            "d3b4")
    assert_equal(okm, OpenSSL::KDF.hkdf(ikm, salt: salt, info: info, length: l, hash: hash))
  end

  private

  def B(ary)
    [Array(ary).join].pack("H*")
  end
end

end
