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

class TestResolvResourceCAA < Test::Unit::TestCase
  def test_caa_roundtrip
    raw_msg = "\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00\x03new\x07example\x03com\x00\x01\x01\x00\x01\x00\x00\x00\x00\x00\x16\x00\x05issueca1.example.net\xC0\x0C\x01\x01\x00\x01\x00\x00\x00\x00\x00\x0C\x80\x03tbsUnknown".b

    m = Resolv::DNS::Message.new(0)
    m.add_answer('new.example.com', 0, Resolv::DNS::Resource::IN::CAA.new(0, 'issue', 'ca1.example.net'))
    m.add_answer('new.example.com', 0, Resolv::DNS::Resource::IN::CAA.new(128, 'tbs', 'Unknown'))
    assert_equal raw_msg, m.encode

    m = Resolv::DNS::Message.decode(raw_msg)
    assert_equal 2, m.answer.size
    _, _, caa0 = m.answer[0]
    assert_equal 0, caa0.flags
    assert_equal false, caa0.critical?
    assert_equal 'issue', caa0.tag
    assert_equal 'ca1.example.net', caa0.value
    _, _, caa1 = m.answer[1]
    assert_equal true, caa1.critical?
    assert_equal 128, caa1.flags
    assert_equal 'tbs', caa1.tag
    assert_equal 'Unknown', caa1.value
  end

  def test_caa_stackoverflow
    # gathered in the wild
    raw_msg = "\x8D\x32\x81\x80\x00\x01\x00\x0B\x00\x00\x00\x00\x0Dstackoverflow\x03com\x00\x01\x01\x00\x01\xC0\x0C\x01\x01\x00\x01\x00\x00\x01\x2C\x00\x13\x00\x05issuecomodoca.com\xC0\x0C\x01\x01\x00\x01\x00\x00\x01\x2C\x00\x2D\x00\x05issuedigicert.com; cansignhttpexchanges=yes\xC0\x0C\x01\x01\x00\x01\x00\x00\x01\x2C\x00\x16\x00\x05issueletsencrypt.org\xC0\x0C\x01\x01\x00\x01\x00\x00\x01\x2C\x00\x29\x00\x05issuepki.goog; cansignhttpexchanges=yes\xC0\x0C\x01\x01\x00\x01\x00\x00\x01\x2C\x00\x12\x00\x05issuesectigo.com\xC0\x0C\x01\x01\x00\x01\x00\x00\x01\x2C\x00\x17\x00\x09issuewildcomodoca.com\xC0\x0C\x01\x01\x00\x01\x00\x00\x01\x2C\x00\x31\x00\x09issuewilddigicert.com; cansignhttpexchanges=yes\xC0\x0C\x01\x01\x00\x01\x00\x00\x01\x2C\x00\x1A\x00\x09issuewildletsencrypt.org\xC0\x0C\x01\x01\x00\x01\x00\x00\x01\x2C\x00\x2D\x00\x09issuewildpki.goog; cansignhttpexchanges=yes\xC0\x0C\x01\x01\x00\x01\x00\x00\x01\x2C\x00\x16\x00\x09issuewildsectigo.com\xC0\x0C\x01\x01\x00\x01\x00\x00\x01\x2C\x00\x2D\x80\x05iodefmailto:sysadmin-team@stackoverflow.com".b

    m = Resolv::DNS::Message.decode(raw_msg)
    assert_equal 11, m.answer.size
    _, _, caa3 = m.answer[3]
    assert_equal 0, caa3.flags
    assert_equal 'issue', caa3.tag
    assert_equal 'pki.goog; cansignhttpexchanges=yes', caa3.value
    _, _, caa8 = m.answer[8]
    assert_equal 0, caa8.flags
    assert_equal 'issuewild', caa8.tag
    assert_equal 'pki.goog; cansignhttpexchanges=yes', caa8.value
    _, _, caa10 = m.answer[10]
    assert_equal 128, caa10.flags
    assert_equal 'iodef', caa10.tag
    assert_equal 'mailto:sysadmin-team@stackoverflow.com', caa10.value
  end

  def test_caa_flags
    assert_equal 255,
      Resolv::DNS::Resource::IN::CAA.new(255, 'issue', 'ca1.example.net').flags
    assert_raise(ArgumentError) do
      Resolv::DNS::Resource::IN::CAA.new(256, 'issue', 'ca1.example.net')
    end

    assert_raise(ArgumentError) do
      Resolv::DNS::Resource::IN::CAA.new(-1, 'issue', 'ca1.example.net')
    end
  end

  def test_caa_tag
    assert_raise(ArgumentError, 'Empty tag should be rejected') do
      Resolv::DNS::Resource::IN::CAA.new(0, '', 'ca1.example.net')
    end

    assert_equal '123456789012345',
      Resolv::DNS::Resource::IN::CAA.new(0, '123456789012345', 'ca1.example.net').tag
    assert_raise(ArgumentError, 'Tag longer than 15 bytes should be rejected') do
      Resolv::DNS::Resource::IN::CAA.new(0, '1234567890123456', 'ca1.example.net')
    end
  end
end
