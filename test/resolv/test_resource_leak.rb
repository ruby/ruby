# frozen_string_literal: false
require 'test/unit'
require 'resolv'

# Decoding a response with unknown (type, class) pairs or unknown SvcParamKeys
# used to register a generated class permanently, so a malicious response could
# exhaust memory even after the response was discarded.
class TestResolvResourceLeak < Test::Unit::TestCase
  # Number of dynamically-registered "Type<n>_Class<n>" constants on +mod+.
  def type_const_count(mod)
    mod.constants(false).count { |c| c.to_s.match?(/\AType\d+_Class\d+\z/) }
  end

  def svcparam_key_const_count
    Resolv::DNS::SvcParam::Generic.constants(false).count { |c| c.to_s.match?(/\AKey\d+\z/) }
  end

  # A DNS response whose answer section holds +count+ RRs, each with a distinct
  # unknown (type, class) pair.
  def unknown_typeclass_response(count)
    body = "".b
    count.times do |i|
      type  = 40000 + i
      klass = 60000
      rdata = "\x01\x02\x03".b
      body << "\x00".b                                    # NAME = root
      body << [type, klass, 0, rdata.bytesize].pack('nnNn')
      body << rdata
    end
    header = "\x00\x00\x00\x00".b + [0, count, 0, 0].pack('nnnn')
    (header + body).b
  end

  # An SVCB RR (type 64) carrying +count+ distinct unknown SvcParamKeys.
  def unknown_svcparam_response(count)
    rdata = "".b
    rdata << [1].pack('n')                                # SvcPriority
    rdata << "\x03foo\x07example\x03com\x00".b            # TargetName
    count.times do |i|
      key = 1000 + i
      val = "x".b
      rdata << [key, val.bytesize].pack('nn') << val
    end
    header = "\x00\x00\x00\x00".b + [0, 1, 0, 0].pack('nnnn')
    name   = "\x07example\x03com\x00".b
    rr     = name + [64, 1, 0, rdata.bytesize].pack('nnNn') + rdata
    (header + rr).b
  end

  def test_unknown_typeclass_does_not_leak_classes
    resource = Resolv::DNS::Resource
    generic  = Resolv::DNS::Resource::Generic

    before_resource = type_const_count(resource)
    before_generic  = type_const_count(generic)

    [100, 1000].each do |count|
      msg = unknown_typeclass_response(count)
      3.times { Resolv::DNS::Message.decode(msg) }
    end
    GC.start

    assert_equal before_resource, type_const_count(resource),
      'decoding unknown (type, class) RRs must not register new Resource constants'
    assert_equal before_generic, type_const_count(generic),
      'decoding unknown (type, class) RRs must not register new Generic constants'
  end

  def test_unknown_svcparam_key_does_not_leak_classes
    class_hash = Resolv::DNS::SvcParam::ClassHash

    before_consts = svcparam_key_const_count
    before_hash   = class_hash.size

    [100, 1000].each do |count|
      msg = unknown_svcparam_response(count)
      3.times { Resolv::DNS::Message.decode(msg) }
    end
    GC.start

    assert_equal before_consts, svcparam_key_const_count,
      'decoding unknown SvcParamKeys must not register new Generic constants'
    assert_equal before_hash, class_hash.size,
      'decoding unknown SvcParamKeys must not grow SvcParam::ClassHash'
  end

  # Dropping the permanent registration must not break decoding of the unknown
  # values themselves.
  def test_unknown_values_still_decode
    msg = Resolv::DNS::Message.decode(unknown_typeclass_response(3))
    assert_equal 3, msg.answer.size
    _, _, rr = msg.answer.first
    assert_kind_of Resolv::DNS::Resource::Generic, rr
    assert_equal "\x01\x02\x03".b, rr.data

    msg = Resolv::DNS::Message.decode(unknown_svcparam_response(3))
    _, _, svcb = msg.answer.first
    assert_equal 3, svcb.params.count
    assert_equal "x".b, svcb.params[:key1000].value
  end
end
