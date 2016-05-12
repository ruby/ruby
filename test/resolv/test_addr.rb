# frozen_string_literal: false
require 'test/unit'
require 'resolv'
require 'socket'
require 'tempfile'

class TestResolvAddr < Test::Unit::TestCase
  def test_invalid_ipv4_address
    assert_not_match(Resolv::IPv4::Regex, "1.2.3.256", "[ruby-core:29501]")
    1000.times {|i|
      if i < 256
        assert_match(Resolv::IPv4::Regex, "#{i}.#{i}.#{i}.#{i}")
      else
        assert_not_match(Resolv::IPv4::Regex, "#{i}.#{i}.#{i}.#{i}")
      end
    }
  end

  def test_invalid_byte_comment
    bug9273 = '[ruby-core:59239] [Bug #9273]'
    Tempfile.create('resolv_test_addr_') do |tmpfile|
      tmpfile.print("\xff\x00\x40")
      tmpfile.close
      hosts = Resolv::Hosts.new(tmpfile.path)
      assert_nothing_raised(ArgumentError, bug9273) do
        hosts.each_address("") {break}
      end
    end
  end
end
