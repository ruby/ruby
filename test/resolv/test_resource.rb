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

  def test_srv_no_compress
    # Domain name in SRV RDATA should not be compressed
    issue29 = 'https://github.com/ruby/resolv/issues/29'
    m = Resolv::DNS::Message.new(0)
    m.add_answer('example.com', 0, Resolv::DNS::Resource::IN::SRV.new(0, 0, 0, 'www.example.com'))
    assert_equal "\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x07example\x03com\x00\x00\x21\x00\x01\x00\x00\x00\x00\x00\x17\x00\x00\x00\x00\x00\x00\x03www\x07example\x03com\x00", m.encode, issue29
  end
end
