require 'test/unit'

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

  def test_shared_thread
    ff = proc {|n| true if n==3..n==5}
    v = 1..9
    a = true
    th = Thread.new {
      v.select {|i|
        Thread.pass while a
        ff[i].tap {a = true}
      }
    }
    v1 = v.select {|i|
      Thread.pass until a
      ff[i].tap {a = false}
    }
    v2 = th.value
    expected = [3, 4, 5]
    mesg = 'flip-flop should be separated per threads'
    assert_equal(expected, v1, mesg)
    assert_equal(expected, v2, mesg)
  end
end
