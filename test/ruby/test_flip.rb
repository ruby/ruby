require 'test/unit'
require_relative 'envutil'

class TestFlip < Test::Unit::TestCase
  def test_hidden_key
    bug6899 = '[ruby-core:47253]'
    foo = "foor"
    bar = "bar"
    assert_nothing_raised(NotImplementedError, bug6899) do
      2000.times {eval %[(foo..bar) ? 1 : 2]}
    end
  end
end
