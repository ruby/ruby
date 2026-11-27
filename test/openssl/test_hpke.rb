# frozen_string_literal: true
require_relative 'utils'

if defined?(OpenSSL)

class OpenSSL::TestHPKE < OpenSSL::TestCase
  def setup
    super
    # OpenSSL's FIPS provider does not implement the DHKEM KEM encapsulation
    # used by HPKE, so no HPKE operation can complete a round-trip under FIPS.
    # The whole feature is therefore omitted in FIPS mode.
    omit_on_fips
    # OpenSSL::HPKE is only defined when the extension was built against
    # OpenSSL >= 3.2.0 (LibreSSL and AWS-LC do not provide the HPKE API).
    unless openssl?(3, 2, 0)
      omit "HPKE is not supported by this OpenSSL"
    end
  end

  def test_suite_new_with_names
    suite = OpenSSL::HPKE::Suite.new("X25519", "hkdf-sha256", "aes-128-gcm")
    assert_equal(0x0020, suite.kem_id)
    assert_equal(0x0001, suite.kdf_id)
    assert_equal(0x0001, suite.aead_id)
  end

  def test_suite_names_are_case_insensitive
    suite = OpenSSL::HPKE::Suite.new("x25519", "HKDF-SHA256", "AES-128-GCM")
    assert_equal(0x0020, suite.kem_id)
    assert_equal(0x0001, suite.kdf_id)
    assert_equal(0x0001, suite.aead_id)
  end

  def test_suite_new_with_integer_ids
    # IANA IDs as carried on the wire (e.g. by ECH): X25519 / HKDF-SHA256 /
    # AES-128-GCM. All three args must be Integers to take this path.
    suite = OpenSSL::HPKE::Suite.new(0x0020, 0x0001, 0x0001)
    assert_equal(0x0020, suite.kem_id)
    assert_equal(0x0001, suite.kdf_id)
    assert_equal(0x0001, suite.aead_id)
  end

  def test_suite_is_frozen_after_initialization
    assert_predicate(x25519_suite, :frozen?)
    assert_raise(FrozenError) do
      x25519_suite.instance_variable_set(:@foo, 1)
    end
  end

  def test_suite_new_with_integer_ids_validates_suite
    # Well-formed uint16 IDs that are not a supported HPKE algorithm.
    assert_raise(OpenSSL::HPKE::HPKEError) do
      OpenSSL::HPKE::Suite.new(0xBEEF, 0x0001, 0x0001)
    end
  end

  def test_suite_new_with_integer_ids_out_of_range
    assert_raise(OpenSSL::HPKE::HPKEError) do
      OpenSSL::HPKE::Suite.new(0x10000, 0x0001, 0x0001)
    end
  end

  def test_suite_new_unknown_name_raises
    assert_raise(OpenSSL::HPKE::HPKEError) do
      OpenSSL::HPKE::Suite.new("bogus", "hkdf-sha256", "aes-128-gcm")
    end
    assert_raise(OpenSSL::HPKE::HPKEError) do
      OpenSSL::HPKE::Suite.new("X25519", "bogus", "aes-128-gcm")
    end
    assert_raise(OpenSSL::HPKE::HPKEError) do
      OpenSSL::HPKE::Suite.new("X25519", "hkdf-sha256", "bogus")
    end
  end

  def test_keygen_returns_pkey
    pkey = OpenSSL::HPKE.keygen(x25519_suite)
    assert_kind_of(OpenSSL::PKey::PKey, pkey)
  end

  def test_keygen_for_all_kems
    ["P-256", "P-384", "P-521", "X25519", "X448"].each do |kem|
      suite = OpenSSL::HPKE::Suite.new(kem, "hkdf-sha256", "aes-128-gcm")
      assert_kind_of(OpenSSL::PKey::PKey,
                     OpenSSL::HPKE.keygen(suite),
                     "keygen failed for KEM #{kem}")
    end
  end

  def test_keygen_rejects_non_suite
    assert_raise(OpenSSL::HPKE::HPKEError) do
      OpenSSL::HPKE.keygen("not a suite")
    end
  end

  def test_base_mode_roundtrip_x25519
    assert_hpke_roundtrip(x25519_suite)
  end

  def test_base_mode_roundtrip_x448
    assert_hpke_roundtrip(
      OpenSSL::HPKE::Suite.new("X448", "hkdf-sha512", "aes-256-gcm"))
  end

  def test_base_mode_roundtrip_p256
    assert_hpke_roundtrip(
      OpenSSL::HPKE::Suite.new("P-256", "hkdf-sha256", "aes-128-gcm"))
  end

  def test_base_mode_roundtrip_chacha20poly1305
    assert_hpke_roundtrip(
      OpenSSL::HPKE::Suite.new("X25519", "hkdf-sha256", "chacha20-poly1305"))
  end

  def test_seal_open_multiple_messages_in_order
    sender, receiver = paired_contexts(x25519_suite)
    messages = ["first", "second", "third"]
    ciphertexts = messages.map { |m| sender.seal("aad", m) }
    opened = ciphertexts.map { |c| receiver.open("aad", c) }
    assert_equal(messages, opened)
  end

  def test_open_fails_with_wrong_aad
    sender, receiver = paired_contexts(x25519_suite)
    ct = sender.seal("correct aad", "secret")
    assert_raise(OpenSSL::HPKE::HPKEError) do
      receiver.open("wrong aad", ct)
    end
  end

  def test_open_fails_on_tampered_ciphertext
    sender, receiver = paired_contexts(x25519_suite)
    ct = sender.seal("aad", "secret message")
    tampered = ct.dup
    tampered.setbyte(0, tampered.getbyte(0) ^ 0xff)
    assert_raise(OpenSSL::HPKE::HPKEError) do
      receiver.open("aad", tampered)
    end
  end

  def test_export_secret_agreement
    sender, receiver = paired_contexts(x25519_suite)
    sender_secret = sender.export(32, "context label")
    receiver_secret = receiver.export(32, "context label")
    assert_equal(32, sender_secret.bytesize)
    assert_equal(sender_secret, receiver_secret)
  end

  def test_export_different_labels_differ
    sender, = paired_contexts(x25519_suite)
    assert_not_equal(sender.export(32, "label a"), sender.export(32, "label b"))
  end

  def test_export_only_suite
    suite = OpenSSL::HPKE::Suite.new("X25519", "hkdf-sha256", "exporter")
    sender, receiver = paired_contexts(suite)
    assert_equal(sender.export(32, "label"), receiver.export(32, "label"))
    # The export-only AEAD cannot seal or open.
    assert_raise(OpenSSL::HPKE::HPKEError) { sender.seal("aad", "msg") }
  end

  def test_context_cannot_be_reinitialized
    suite = x25519_suite
    sender = OpenSSL::HPKE::Context::Sender.new(suite)
    assert_raise(TypeError) do
      sender.send(:initialize, suite)
    end

    receiver = OpenSSL::HPKE::Context::Receiver.new(suite)
    assert_raise(TypeError) do
      receiver.send(:initialize, suite)
    end
  end

  def test_string_arguments_are_required
    suite = x25519_suite
    pkey = OpenSSL::HPKE.keygen(suite)
    sender = OpenSSL::HPKE::Context::Sender.new(suite)
    assert_raise(TypeError) { sender.encap(12345, "info") }
    assert_raise(TypeError) { sender.encap(public_key_bytes(pkey), 12345) }
  end

  private

  def x25519_suite
    OpenSSL::HPKE::Suite.new("X25519", "hkdf-sha256", "aes-128-gcm")
  end

  # The KEM public key passed to #encap is the recipient's public key in the
  # KEM's wire encoding: the raw key for X25519/X448, the uncompressed point
  # for the NIST curves.
  def public_key_bytes(pkey)
    if pkey.is_a?(OpenSSL::PKey::EC)
      pkey.public_key.to_octet_string(:uncompressed)
    else
      pkey.raw_public_key
    end
  end

  # Returns an established [sender, receiver] pair sharing the same context.
  def paired_contexts(suite, info: "shared info")
    pkey = OpenSSL::HPKE.keygen(suite)
    sender = OpenSSL::HPKE::Context::Sender.new(suite)
    enc = sender.encap(public_key_bytes(pkey), info)
    receiver = OpenSSL::HPKE::Context::Receiver.new(suite)
    assert_equal(true, receiver.decap(enc, pkey, info))
    [sender, receiver]
  end

  def assert_hpke_roundtrip(suite, info: "some info", aad: "some aad",
                            message: "hello hpke")
    pkey = OpenSSL::HPKE.keygen(suite)

    sender = OpenSSL::HPKE::Context::Sender.new(suite)
    enc = sender.encap(public_key_bytes(pkey), info)
    ct = sender.seal(aad, message)

    receiver = OpenSSL::HPKE::Context::Receiver.new(suite)
    assert_equal(true, receiver.decap(enc, pkey, info))
    assert_equal(message, receiver.open(aad, ct))
  end
end

end
