require 'test/unit'
require 'resolv'
require 'socket'

class TestResolvAddr < Test::Unit::TestCase
  def test_invalid_ipv4_address
    assert(Resolv::IPv4::Regex !~ "1.2.3.256", "[ruby-core:29501]")
    1000.times {|i|
      if i < 256
        assert(Resolv::IPv4::Regex =~ "#{i}.#{i}.#{i}.#{i}")
      else
        assert(Resolv::IPv4::Regex !~ "#{i}.#{i}.#{i}.#{i}")
      end
    }
  end
end
