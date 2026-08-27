# frozen_string_literal: false
require 'test/unit'
require 'resolv'

class TestResolvResource < Test::Unit::TestCase
  def setup
    address = "192.168.0.1"
    @name1 = Resolv::DNS::Resource::IN::A.new(address)
    @name1.instance_variable_set(:@ttl, 100)
    @name2 = Resolv::DNS::Resource::IN::A.new(address)
  end

  def test_equality
    bug10857 = '[ruby-core:68128] [Bug #10857]'
    assert_equal(@name1, @name2, bug10857)
  end

  def test_hash
    bug10857 = '[ruby-core:68128] [Bug #10857]'
    assert_equal(@name1.hash, @name2.hash, bug10857)
  end

  def test_coord
    Resolv::LOC::Coord.create('1 2 1.1 N')
  end

  # Decoding an unknown (type, class) pair builds a fresh class every time, so
  # equality must not rest on the class identity.
  def test_generic_equality
    wire = generic_answer(40000, "\x01\x02\x03")
    rr1 = decode_generic(wire)
    rr2 = decode_generic(wire)

    assert_not_same rr1.class, rr2.class
    assert_equal rr1, rr2
    assert rr1.eql?(rr2)
    assert_equal rr1.hash, rr2.hash
    assert_equal Resolv::DNS::Message.decode(wire), Resolv::DNS::Message.decode(wire)
  end

  # Any descendant counts, not just a class create returned.
  def test_generic_equality_between_descendants
    generic = Resolv::DNS::Resource::Generic
    direct = generic.create(40000, 60000)
    descendant = Class.new(generic.create(40000, 60000))

    assert_equal direct.new("\x01\x02\x03"), descendant.new("\x01\x02\x03")
    assert_equal descendant.new("\x01\x02\x03"), direct.new("\x01\x02\x03")
    assert_equal generic.new("\x01\x02\x03"), generic.new("\x01\x02\x03")
    assert_not_equal direct.new("\x01\x02\x03"),
      Class.new(generic.create(40001, 60000)).new("\x01\x02\x03")
  end

  def test_generic_inequality
    rr = decode_generic(generic_answer(40000, "\x01\x02\x03"))

    assert_not_equal rr, decode_generic(generic_answer(40001, "\x01\x02\x03"))
    assert_not_equal rr, decode_generic(generic_answer(40000, "\x09\x09\x09"))
    assert_not_equal rr, Resolv::DNS::Resource::IN::A.new("192.168.0.1")
  end

  # A question holds the resource class itself, so it needs the same treatment.
  def test_generic_question_equality
    wire = generic_question(40000)

    assert_equal Resolv::DNS::Message.decode(wire), Resolv::DNS::Message.decode(wire)
    assert_not_equal Resolv::DNS::Message.decode(wire),
      Resolv::DNS::Message.decode(generic_question(40001))
  end

  private def header(qdcount, ancount)
    "\x00\x00\x00\x00".b + [qdcount, ancount, 0, 0].pack('nnnn')
  end

  private def generic_answer(type, rdata)
    rdata = rdata.b
    (header(0, 1) + "\x00".b + [type, 60000, 0, rdata.bytesize].pack('nnNn') + rdata).b
  end

  private def generic_question(type)
    (header(1, 0) + "\x07example\x03com\x00".b + [type, 60000].pack('nn')).b
  end

  private def decode_generic(wire)
    Resolv::DNS::Message.decode(wire).answer.first[2]
  end

  def test_srv_no_compress
    # Domain name in SRV RDATA should not be compressed
    issue29 = 'https://github.com/ruby/resolv/issues/29'
    m = Resolv::DNS::Message.new(0)
    m.add_answer('example.com', 0, Resolv::DNS::Resource::IN::SRV.new(0, 0, 0, 'www.example.com'))
    assert_equal "\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x07example\x03com\x00\x00\x21\x00\x01\x00\x00\x00\x00\x00\x17\x00\x00\x00\x00\x00\x00\x03www\x07example\x03com\x00", m.encode, issue29
  end
end
