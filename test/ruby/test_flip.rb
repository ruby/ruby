# frozen_string_literal: false
require 'test/unit'

class TestFlip < Test::Unit::TestCase
  def test_flip_flop
    assert_equal [4,5], (1..9).select {|n| true if (n==4)..(n==5)}
    assert_equal [4,5], (1..9).select {|n| true if (n==4)...(n==5)}
    assert_equal [2], (1..9).select {|n| true if (n==2)..(n%2).zero?}
    assert_equal [2,3,4], (1..9).select {|n| true if (n==2)...(n%2).zero?}
    assert_equal [4,5,7,8], (1..9).select {|n| true if (n==4)...(n==5) or (n==7)...(n==8)}
    assert_equal [nil, 2, 3, 4, nil], (1..5).map {|x| x if (x==2..x==4)}
    assert_equal [1, nil, nil, nil, 5], (1..5).map {|x| x if !(x==2..x==4)}
  end

  def test_hidden_key
    bug6899 = '[ruby-core:47253]'
    foo = "foor"
    bar = "bar"
    assert_nothing_raised(NotImplementedError, bug6899) do
      2000.times {eval %[(foo..bar) ? 1 : 2]}
    end
    foo = bar
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

  def test_input_line_number_range
    bug12947 = '[ruby-core:78162] [Bug #12947]'
    ary = b1 = b2 = nil
    EnvUtil.suppress_warning do
      b1 = eval("proc {|i| i if 2..4}")
      b2 = eval("proc {|i| if 2..4; i; end}")
    end
    IO.pipe {|r, w|
      th = Thread.start {(1..5).each {|i| w.puts i};w.close}
      ary = r.map {|i| b1.call(i.chomp)}
      th.join
    }
    assert_equal([nil, "2", "3", "4", nil], ary, bug12947)
    IO.pipe {|r, w|
      th = Thread.start {(1..5).each {|i| w.puts i};w.close}
      ary = r.map {|i| b2.call(i.chomp)}
      th.join
    }
    assert_equal([nil, "2", "3", "4", nil], ary, bug12947)
  end
end
