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
end
