require 'minitest/autorun'

module DTrace
  class TestObjectCreate < MiniTest::Unit::TestCase
    def setup
      skip "must be setuid 0 to run dtrace tests" unless Process.euid == 0
    end

    def test_zomg
      flunk "rawr"
    end
  end
end
