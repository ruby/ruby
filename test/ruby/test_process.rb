require 'test/unit'

class TestProcess < Test::Unit::TestCase
  def test_rlimit
    begin
      Process.getrlimit
    rescue NotImplementedError
      assert_raise(NotImplementedError) { Process.setrlimit }
    rescue ArgumentError
      assert_raise(ArgumentError) { Process.setrlimit }
    end
  end
end
