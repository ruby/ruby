# frozen_string_literal: false
require_relative 'utils'

if defined?(OpenSSL::TestUtils) && defined?(OpenSSL::PKey::EC)

class OpenSSL::TestEC < Test::Unit::TestCase
  def setup
    @data1 = 'foo'
    @data2 = 'bar' * 1000 # data too long for DSA sig

    @groups = []
    @keys = []

    OpenSSL::PKey::EC.builtin_curves.each do |curve, comment|
      next if curve.start_with?("Oakley") # Oakley curves are not suitable for ECDSA
      group = OpenSSL::PKey::EC::Group.new(curve)

      key = OpenSSL::PKey::EC.new(group)
      key.generate_key

      @groups << group
      @keys << key
    end
  end

  def compare_keys(k1, k2)
    assert_equal(k1.to_pem, k2.to_pem)
  end

  def test_builtin_curves
    assert(!OpenSSL::PKey::EC.builtin_curves.empty?)
  end

  def test_curve_names
    @groups.each_with_index do |group, idx|
      key = @keys[idx]
      assert_equal(group.curve_name, key.group.curve_name)
    end
  end

  def test_check_key
    for key in @keys
      assert_equal(key.check_key, true)
      assert_equal(key.private_key?, true)
      assert_equal(key.public_key?, true)
    end
  end

  def test_group_encoding
    for group in @groups
      for meth in [:to_der, :to_pem]
        txt = group.send(meth)
        gr = OpenSSL::PKey::EC::Group.new(txt)

        assert_equal(txt, gr.send(meth))

        assert_equal(group.generator.to_bn, gr.generator.to_bn)
        assert_equal(group.cofactor, gr.cofactor)
        assert_equal(group.order, gr.order)
        assert_equal(group.seed, gr.seed)
        assert_equal(group.degree, gr.degree)
      end
    end
  end

  def test_key_encoding
    for key in @keys
      group = key.group

      for meth in [:to_der, :to_pem]
        txt = key.send(meth)
        assert_equal(txt, OpenSSL::PKey::EC.new(txt).send(meth))
      end

      bn = key.public_key.to_bn
      assert_equal(bn, OpenSSL::PKey::EC::Point.new(group, bn).to_bn)
    end
  end

  def test_set_keys
    for key in @keys
      k = OpenSSL::PKey::EC.new
      k.group = key.group
      k.private_key = key.private_key
      k.public_key = key.public_key

      compare_keys(key, k)
    end
  end

  def test_dsa_sign_verify
    for key in @keys
      sig = key.dsa_sign_asn1(@data1)
      assert(key.dsa_verify_asn1(@data1, sig))
    end
  end

  def test_dsa_sign_asn1_FIPS186_3
    for key in @keys
      size = key.group.order.num_bits / 8 + 1
      dgst = (1..size).to_a.pack('C*')
      begin
        sig = key.dsa_sign_asn1(dgst)
        # dgst is auto-truncated according to FIPS186-3 after openssl-0.9.8m
        assert(key.dsa_verify_asn1(dgst + "garbage", sig))
      rescue OpenSSL::PKey::ECError => e
        # just an exception for longer dgst before openssl-0.9.8m
        assert_equal('ECDSA_sign: data too large for key size', e.message)
        # no need to do following tests
        return
      end
    end
  end

  def test_dh_compute_key
    for key in @keys
      k = OpenSSL::PKey::EC.new(key.group)
      k.generate_key

      puba = key.public_key
      pubb = k.public_key
      a = key.dh_compute_key(pubb)
      b = k.dh_compute_key(puba)
      assert_equal(a, b)
    end
  end

  def test_read_private_key_der
    ec = OpenSSL::TestUtils::TEST_KEY_EC_P256V1
    der = ec.to_der
    ec2 = OpenSSL::PKey.read(der)
    assert(ec2.private_key?)
    assert_equal(der, ec2.to_der)
    assert_equal([], OpenSSL.errors)
  end

  def test_read_private_key_pem
    ec = OpenSSL::TestUtils::TEST_KEY_EC_P256V1
    pem = ec.to_pem
    ec2 = OpenSSL::PKey.read(pem)
    assert(ec2.private_key?)
    assert_equal(pem, ec2.to_pem)
    assert_equal([], OpenSSL.errors)
  end

  def test_read_public_key_der
    ec = OpenSSL::TestUtils::TEST_KEY_EC_P256V1
    ec2 = OpenSSL::PKey::EC.new(ec.group)
    ec2.public_key = ec.public_key
    der = ec2.to_der
    ec3 = OpenSSL::PKey.read(der)
    assert(!ec3.private_key?)
    assert_equal(der, ec3.to_der)
    assert_equal([], OpenSSL.errors)
  end

  def test_read_public_key_pem
    ec = OpenSSL::TestUtils::TEST_KEY_EC_P256V1
    ec2 = OpenSSL::PKey::EC.new(ec.group)
    ec2.public_key = ec.public_key
    pem = ec2.to_pem
    ec3 = OpenSSL::PKey.read(pem)
    assert(!ec3.private_key?)
    assert_equal(pem, ec3.to_pem)
    assert_equal([], OpenSSL.errors)
  end

  def test_read_private_key_pem_pw
    ec = OpenSSL::TestUtils::TEST_KEY_EC_P256V1
    pem = ec.to_pem(OpenSSL::Cipher.new('AES-128-CBC'), 'secret')
    #callback form for password
    ec2 = OpenSSL::PKey.read(pem) do
      'secret'
    end
    assert(ec2.private_key?)
    # pass password directly
    ec2 = OpenSSL::PKey.read(pem, 'secret')
    assert(ec2.private_key?)
    #omit pem equality check, will be different due to cipher iv
    assert_equal([], OpenSSL.errors)
  end

  def test_export_password_length
    key = OpenSSL::TestUtils::TEST_KEY_EC_P256V1
    assert_raise(OpenSSL::OpenSSLError) do
      key.export(OpenSSL::Cipher.new('AES-128-CBC'), 'sec')
    end
    pem = key.export(OpenSSL::Cipher.new('AES-128-CBC'), 'secr')
    assert(pem)
  end

  def test_ec_point_mul
    ec = OpenSSL::TestUtils::TEST_KEY_EC_P256V1
    p1 = ec.public_key
    bn1 = OpenSSL::BN.new('10')
    bn2 = OpenSSL::BN.new('20')

    p2 = p1.mul(bn1)
    assert(p1.group == p2.group)
    p2 = p1.mul(bn1, bn2)
    assert(p1.group == p2.group)
    p2 = p1.mul([bn1, bn2], [p1])
    assert(p1.group == p2.group)
    p2 = p1.mul([bn1, bn2], [p1], bn2)
    assert(p1.group == p2.group)
  end

# test Group: asn1_flag, point_conversion

end

end
