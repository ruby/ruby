# frozen_string_literal: false
require_relative 'utils'

if defined?(OpenSSL::TestUtils)

class OpenSSL::TestPKeyDSA < OpenSSL::PKeyTestCase
  def test_private
    key = OpenSSL::PKey::DSA.new(256)
    assert(key.private?)
    key2 = OpenSSL::PKey::DSA.new(key.to_der)
    assert(key2.private?)
    key3 = key.public_key
    assert(!key3.private?)
    key4 = OpenSSL::PKey::DSA.new(key3.to_der)
    assert(!key4.private?)
  end

  def test_new
    key = OpenSSL::PKey::DSA.new 256
    pem  = key.public_key.to_pem
    OpenSSL::PKey::DSA.new pem
    if $0 == __FILE__
      assert_nothing_raised {
        key = OpenSSL::PKey::DSA.new 2048
      }
    end
  end

  def test_new_break
    assert_nil(OpenSSL::PKey::DSA.new(512) { break })
    assert_raise(RuntimeError) do
      OpenSSL::PKey::DSA.new(512) { raise }
    end
  end

  def test_sign_verify
    dsa512 = Fixtures.pkey("dsa512")
    data = "Sign me!"
    if defined?(OpenSSL::Digest::DSS1)
      signature = dsa512.sign(OpenSSL::Digest::DSS1.new, data)
      assert_equal true, dsa512.verify(OpenSSL::Digest::DSS1.new, signature, data)
    end

    return unless openssl?(1, 0, 0)
    signature = dsa512.sign("SHA1", data)
    assert_equal true, dsa512.verify("SHA1", signature, data)

    signature0 = (<<~'end;').unpack("m")[0]
      MCwCFH5h40plgU5Fh0Z4wvEEpz0eE9SnAhRPbkRB8ggsN/vsSEYMXvJwjGg/
      6g==
    end;
    assert_equal true, dsa512.verify("SHA256", signature0, data)
    signature1 = signature0.succ
    assert_equal false, dsa512.verify("SHA256", signature1, data)
  end

  def test_sys_sign_verify
    key = Fixtures.pkey("dsa256")
    data = 'Sign me!'
    digest = OpenSSL::Digest::SHA1.digest(data)
    sig = key.syssign(digest)
    assert(key.sysverify(digest, sig))
  end

  def test_DSAPrivateKey
    # OpenSSL DSAPrivateKey format; similar to RSAPrivateKey
    dsa512 = Fixtures.pkey("dsa512")
    asn1 = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Integer(0),
      OpenSSL::ASN1::Integer(dsa512.p),
      OpenSSL::ASN1::Integer(dsa512.q),
      OpenSSL::ASN1::Integer(dsa512.g),
      OpenSSL::ASN1::Integer(dsa512.pub_key),
      OpenSSL::ASN1::Integer(dsa512.priv_key)
    ])
    key = OpenSSL::PKey::DSA.new(asn1.to_der)
    assert_predicate key, :private?
    assert_same_dsa dsa512, key

    pem = <<~EOF
    -----BEGIN DSA PRIVATE KEY-----
    MIH4AgEAAkEA5lB4GvEwjrsMlGDqGsxrbqeFRh6o9OWt6FgTYiEEHaOYhkIxv0Ok
    RZPDNwOG997mDjBnvDJ1i56OmS3MbTnovwIVAJgub/aDrSDB4DZGH7UyarcaGy6D
    AkB9HdFw/3td8K4l1FZHv7TCZeJ3ZLb7dF3TWoGUP003RCqoji3/lHdKoVdTQNuR
    S/m6DlCwhjRjiQ/lBRgCLCcaAkEAjN891JBjzpMj4bWgsACmMggFf57DS0Ti+5++
    Q1VB8qkJN7rA7/2HrCR3gTsWNb1YhAsnFsoeRscC+LxXoXi9OAIUBG98h4tilg6S
    55jreJD3Se3slps=
    -----END DSA PRIVATE KEY-----
    EOF
    key = OpenSSL::PKey::DSA.new(pem)
    assert_same_dsa dsa512, key

    assert_equal asn1.to_der, dsa512.to_der
    assert_equal pem, dsa512.export
  end

  def test_DSAPrivateKey_encrypted
    # key = abcdef
    dsa512 = Fixtures.pkey("dsa512")
    pem = <<~EOF
    -----BEGIN DSA PRIVATE KEY-----
    Proc-Type: 4,ENCRYPTED
    DEK-Info: AES-128-CBC,F8BB7BFC7EAB9118AC2E3DA16C8DB1D9

    D2sIzsM9MLXBtlF4RW42u2GB9gX3HQ3prtVIjWPLaKBYoToRUiv8WKsjptfZuLSB
    74ZPdMS7VITM+W1HIxo/tjS80348Cwc9ou8H/E6WGat8ZUk/igLOUEII+coQS6qw
    QpuLMcCIavevX0gjdjEIkojBB81TYDofA1Bp1z1zDI/2Zhw822xapI79ZF7Rmywt
    OSyWzFaGipgDpdFsGzvT6//z0jMr0AuJVcZ0VJ5lyPGQZAeVBlbYEI4T72cC5Cz7
    XvLiaUtum6/sASD2PQqdDNpgx/WA6Vs1Po2kIUQIM5TIwyJI0GdykZcYm6xIK/ta
    Wgx6c8K+qBAIVrilw3EWxw==
    -----END DSA PRIVATE KEY-----
    EOF
    key = OpenSSL::PKey::DSA.new(pem, "abcdef")
    assert_same_dsa dsa512, key
    key = OpenSSL::PKey::DSA.new(pem) { "abcdef" }
    assert_same_dsa dsa512, key

    cipher = OpenSSL::Cipher.new("aes-128-cbc")
    exported = dsa512.to_pem(cipher, "abcdef\0\1")
    assert_same_dsa dsa512, OpenSSL::PKey::DSA.new(exported, "abcdef\0\1")
    assert_raise(OpenSSL::PKey::DSAError) {
      OpenSSL::PKey::DSA.new(exported, "abcdef")
    }
  end

  def test_PUBKEY
    dsa512 = Fixtures.pkey("dsa512")
    asn1 = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Sequence([
        OpenSSL::ASN1::ObjectId("DSA"),
        OpenSSL::ASN1::Sequence([
          OpenSSL::ASN1::Integer(dsa512.p),
          OpenSSL::ASN1::Integer(dsa512.q),
          OpenSSL::ASN1::Integer(dsa512.g)
        ])
      ]),
      OpenSSL::ASN1::BitString(
        OpenSSL::ASN1::Integer(dsa512.pub_key).to_der
      )
    ])
    key = OpenSSL::PKey::DSA.new(asn1.to_der)
    assert_not_predicate key, :private?
    assert_same_dsa dup_public(dsa512), key

    pem = <<~EOF
    -----BEGIN PUBLIC KEY-----
    MIHxMIGoBgcqhkjOOAQBMIGcAkEA5lB4GvEwjrsMlGDqGsxrbqeFRh6o9OWt6FgT
    YiEEHaOYhkIxv0OkRZPDNwOG997mDjBnvDJ1i56OmS3MbTnovwIVAJgub/aDrSDB
    4DZGH7UyarcaGy6DAkB9HdFw/3td8K4l1FZHv7TCZeJ3ZLb7dF3TWoGUP003RCqo
    ji3/lHdKoVdTQNuRS/m6DlCwhjRjiQ/lBRgCLCcaA0QAAkEAjN891JBjzpMj4bWg
    sACmMggFf57DS0Ti+5++Q1VB8qkJN7rA7/2HrCR3gTsWNb1YhAsnFsoeRscC+LxX
    oXi9OA==
    -----END PUBLIC KEY-----
    EOF
    key = OpenSSL::PKey::DSA.new(pem)
    assert_same_dsa dup_public(dsa512), key

    assert_equal asn1.to_der, dup_public(dsa512).to_der
    assert_equal pem, dup_public(dsa512).export
  end

  def test_read_DSAPublicKey_pem
    # TODO: where is the standard? PKey::DSA.new can read only PEM
    p = 12260055936871293565827712385212529106400444521449663325576634579961635627321079536132296996623400607469624537382977152381984332395192110731059176842635699
    q = 979494906553787301107832405790107343409973851677
    g = 3731695366899846297271147240305742456317979984190506040697507048095553842519347835107669437969086119948785140453492839427038591924536131566350847469993845
    y = 10505239074982761504240823422422813362721498896040719759460296306305851824586095328615844661273887569281276387605297130014564808567159023649684010036304695
    pem = <<-EOF
-----BEGIN DSA PUBLIC KEY-----
MIHfAkEAyJSJ+g+P/knVcgDwwTzC7Pwg/pWs2EMd/r+lYlXhNfzg0biuXRul8VR4
VUC/phySExY0PdcqItkR/xYAYNMbNwJBAOoV57X0FxKO/PrNa/MkoWzkCKV/hzhE
p0zbFdsicw+hIjJ7S6Sd/FlDlo89HQZ2FuvWJ6wGLM1j00r39+F2qbMCFQCrkhIX
SG+is37hz1IaBeEudjB2HQJAR0AloavBvtsng8obsjLb7EKnB+pSeHr/BdIQ3VH7
fWLOqqkzFeRrYMDzUpl36XktY6Yq8EJYlW9pCMmBVNy/dQ==
-----END DSA PUBLIC KEY-----
    EOF
    key = OpenSSL::PKey::DSA.new(pem)
    assert(key.public?)
    assert(!key.private?)
    assert_equal(p, key.p)
    assert_equal(q, key.q)
    assert_equal(g, key.g)
    assert_equal(y, key.pub_key)
    assert_equal(nil, key.priv_key)
  end

  def test_dup
    key = OpenSSL::PKey::DSA.new(256)
    key2 = key.dup
    assert_equal key.params, key2.params
    key2.set_pqg(key2.p + 1, key2.q, key2.g)
    assert_not_equal key.params, key2.params
  end

  private
  def assert_same_dsa(expected, key)
    check_component(expected, key, [:p, :q, :g, :pub_key, :priv_key])
  end
end

end
