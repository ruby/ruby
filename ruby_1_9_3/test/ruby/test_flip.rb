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

  def test_shared_eval
    bug7671 = '[ruby-core:51296]'
    vs = (1..9).to_a
    vs.select {|n| if n==2..n==16 then 1 end}
    v = eval("vs.select {|n| if n==3..n==6 then 1 end}")
    assert_equal([*3..6], v, bug7671)
  end
end
