# frozen_string_literal: false
require 'test/unit'

class TestArithmeticSequence < Test::Unit::TestCase
  def test_new
    assert_raise(NoMethodError) { Enumerator::ArithmeticSequence.new }
  end

  def test_allocate
    assert_raise(TypeError) { Enumerator::ArithmeticSequence.allocate }
  end

  def test_begin
    assert_equal(1, 1.step.begin)
    assert_equal(1, 1.step(10).begin)
    assert_equal(1, 1.step(to: 10).begin)
    assert_equal(1, 1.step(nil).begin)
    assert_equal(1, 1.step(to: nil).begin)
    assert_equal(1, 1.step(by: 2).begin)
    assert_equal(1, 1.step(by: -1).begin)
    assert_equal(1, 1.step(by: nil).begin)
    assert_equal(1, 1.step(10, 2).begin)
    assert_equal(1, 1.step(10, by: 2).begin)
    assert_equal(1, 1.step(to: 10, by: 2).begin)
    assert_equal(10, 10.step(to: 1, by: -1).begin)
    assert_equal(10, 10.step(to: 1, by: -2).begin)
    assert_equal(10, 10.step(to: -1, by: -2).begin)
    assert_equal(10.0, 10.0.step(to: -1.0, by: -2.0).begin)

    assert_equal(3, (3..).step(2).begin)
    assert_equal(4, (4...).step(7).begin)
    assert_equal(nil, (..10).step(9).begin)
    assert_equal(nil, (...11).step(5).begin)
  end

  def test_end
    assert_equal(nil, 1.step.end)
    assert_equal(10, 1.step(10).end)
    assert_equal(10, 1.step(to: 10).end)
    assert_equal(nil, 1.step(nil).end)
    assert_equal(nil, 1.step(to: nil).end)
    assert_equal(nil, 1.step(by: 2).end)
    assert_equal(nil, 1.step(by: -1).end)
    assert_equal(nil, 1.step(by: nil).end)
    assert_equal(10, 1.step(10, 2).end)
    assert_equal(10, 1.step(10, by: 2).end)
    assert_equal(10, 1.step(to: 10, by: 2).end)
    assert_equal(1, 10.step(to: 1, by: -1).end)
    assert_equal(1, 10.step(to: 1, by: -2).end)
    assert_equal(-1, 10.step(to: -1, by: -2).end)
    assert_equal(-1.0, 10.0.step(to: -1.0, by: -2.0).end)

    assert_equal(nil, (3..).step(2).end)
    assert_equal(nil, (4...).step(7).end)
    assert_equal(10, (..10).step(9).end)
    assert_equal(11, (...11).step(5).end)
  end

  def test_exclude_end_p
    assert_equal(false, 1.step.exclude_end?)
    assert_equal(false, 1.step(10).exclude_end?)
    assert_equal(false, 1.step(to: 10).exclude_end?)
    assert_equal(false, 1.step(nil).exclude_end?)
    assert_equal(false, 1.step(to: nil).exclude_end?)
    assert_equal(false, 1.step(by: 2).exclude_end?)
    assert_equal(false, 1.step(by: -1).exclude_end?)
    assert_equal(false, 1.step(by: nil).exclude_end?)
    assert_equal(false, 1.step(10, 2).exclude_end?)
    assert_equal(false, 1.step(10, by: 2).exclude_end?)
    assert_equal(false, 1.step(to: 10, by: 2).exclude_end?)
    assert_equal(false, 10.step(to: 1, by: -1).exclude_end?)
    assert_equal(false, 10.step(to: 1, by: -2).exclude_end?)
    assert_equal(false, 10.step(to: -1, by: -2).exclude_end?)

    assert_equal(false, (3..).step(2).exclude_end?)
    assert_equal(true,  (4...).step(7).exclude_end?)
    assert_equal(false, (..10).step(9).exclude_end?)
    assert_equal(true,  (...11).step(5).exclude_end?)
  end

  def test_step
    assert_equal(1, 1.step.step)
    assert_equal(1, 1.step(10).step)
    assert_equal(1, 1.step(to: 10).step)
    assert_equal(1, 1.step(nil).step)
    assert_equal(1, 1.step(to: nil).step)
    assert_equal(2, 1.step(by: 2).step)
    assert_equal(-1, 1.step(by: -1).step)
    assert_equal(1, 1.step(by: nil).step)
    assert_equal(2, 1.step(10, 2).step)
    assert_equal(2, 1.step(10, by: 2).step)
    assert_equal(2, 1.step(to: 10, by: 2).step)
    assert_equal(-1, 10.step(to: 1, by: -1).step)
    assert_equal(-2, 10.step(to: 1, by: -2).step)
    assert_equal(-2, 10.step(to: -1, by: -2).step)
    assert_equal(-2.0, 10.0.step(to: -1.0, by: -2.0).step)

    assert_equal(2, (3..).step(2).step)
    assert_equal(7, (4...).step(7).step)
    assert_equal(9, (..10).step(9).step)
    assert_equal(5, (...11).step(5).step)
  end

  def test_eq
    seq = 1.step
    assert_equal(seq, seq)
    assert_equal(seq, 1.step)
    assert_equal(seq, 1.step(nil))
  end

  def test_eqq
    seq = 1.step
    assert_operator(seq, :===, seq)
    assert_operator(seq, :===, 1.step)
    assert_operator(seq, :===, 1.step(nil))
  end

  def test_eql_p
    seq = 1.step
    assert_operator(seq, :eql?, seq)
    assert_operator(seq, :eql?, 1.step)
    assert_operator(seq, :eql?, 1.step(nil))
  end

  def test_hash
    seq = 1.step
    assert_equal(seq.hash, seq.hash)
    assert_equal(seq.hash, 1.step.hash)
    assert_equal(seq.hash, 1.step(nil).hash)
    assert_kind_of(String, seq.hash.to_s)
  end

  def test_first
    seq = 1.step
    assert_equal(1, seq.first)
    assert_equal([1], seq.first(1))
    assert_equal([1, 2, 3], seq.first(3))

    seq = 1.step(by: 2)
    assert_equal(1, seq.first)
    assert_equal([1], seq.first(1))
    assert_equal([1, 3, 5], seq.first(3))

    seq = 10.step(by: -2)
    assert_equal(10, seq.first)
    assert_equal([10], seq.first(1))
    assert_equal([10, 8, 6], seq.first(3))

    seq = 1.step(by: 4)
    assert_equal([1, 5, 9], seq.first(3))

    seq = 1.step(10, by: 4)
    assert_equal([1, 5, 9], seq.first(5))

    seq = 1.step(0)
    assert_equal(nil, seq.first)
    assert_equal([], seq.first(1))
    assert_equal([], seq.first(3))

    seq = 1.step(10, by: -1)
    assert_equal(nil, seq.first)
    assert_equal([], seq.first(1))
    assert_equal([], seq.first(3))

    seq = 1.step(10, by: 0)
    assert_equal(1, seq.first)
    assert_equal([1], seq.first(1))
    assert_equal([1, 1, 1], seq.first(3))

    seq = 10.0.step(-1.0, by: -2.0)
    assert_equal(10.0, seq.first)
    assert_equal([10.0], seq.first(1))
    assert_equal([10.0, 8.0, 6.0], seq.first(3))

    seq = (1..).step(2)
    assert_equal(1, seq.first)
    assert_equal([1], seq.first(1))
    assert_equal([1, 3, 5], seq.first(3))

    seq = (..10).step(2)
    assert_equal(nil, seq.first)
    assert_raise(TypeError) { seq.first(1) }
    assert_raise(TypeError) { seq.first(3) }
  end

  def test_first_bug15518
    bug15518 = '[Bug #15518]'
    seq = (1 .. 10.0).step(1)
    five_float_classes = Array.new(5) { Float }
    assert_equal(five_float_classes, seq.first(5).map(&:class), bug15518)
    assert_equal([1.0, 2.0, 3.0, 4.0, 5.0], seq.first(5), bug15518)
    seq = (1 .. Float::INFINITY).step(1)
    assert_equal(five_float_classes, seq.first(5).map(&:class), bug15518)
    assert_equal([1.0, 2.0, 3.0, 4.0, 5.0], seq.first(5), bug15518)
    seq = (1 .. Float::INFINITY).step(1r)
    assert_equal(five_float_classes, seq.first(5).map(&:class), bug15518)
    assert_equal([1.0, 2.0, 3.0, 4.0, 5.0], seq.first(5), bug15518)
  end

  def test_last
    seq = 1.step(10)
    assert_equal(10, seq.last)
    assert_equal([10], seq.last(1))
    assert_equal([8, 9, 10], seq.last(3))

    seq = 1.step(10, 2)
    assert_equal(9, seq.last)
    assert_equal([9], seq.last(1))
    assert_equal([5, 7, 9], seq.last(3))

    seq = 10.step(1, -2)
    assert_equal(2, seq.last)
    assert_equal([2], seq.last(1))
    assert_equal([6, 4, 2], seq.last(3))

    seq = 10.step(-1, -2)
    assert_equal(0, seq.last)

    seq = 1.step(10, 4)
    assert_equal([1, 5, 9], seq.last(5))

    seq = 10.step(1)
    assert_equal(nil, seq.last)
    assert_equal([], seq.last(1))
    assert_equal([], seq.last(5))

    seq = 1.step(10, -1)
    assert_equal(nil, seq.last)
    assert_equal([], seq.last(1))
    assert_equal([], seq.last(5))

    seq = (1..10).step
    assert_equal(10, seq.last)
    assert_equal([10], seq.last(1))
    assert_equal([8, 9, 10], seq.last(3))

    seq = (1...10).step
    assert_equal(9, seq.last)
    assert_equal([9], seq.last(1))
    assert_equal([7, 8, 9], seq.last(3))

    seq = 10.0.step(-3.0, by: -2.0)
    assert_equal(-2.0, seq.last)
    assert_equal([-2.0], seq.last(1))
    assert_equal([2.0, 0.0, -2.0], seq.last(3))
  end

  def test_last_with_float
    res = (1..3).step(2).last(2.0)
    assert_equal([1, 3], res)
    assert_instance_of Integer, res[0]
    assert_instance_of Integer, res[1]

    res = (1..3).step(2).last(5.0)
    assert_equal([1, 3], res)
    assert_instance_of Integer, res[0]
    assert_instance_of Integer, res[1]
  end

  def test_last_with_rational
    res = (1..3).step(2).last(2r)
    assert_equal([1, 3], res)
    assert_instance_of Integer, res[0]
    assert_instance_of Integer, res[1]

    res = (1..3).step(2).last(10/2r)
    assert_equal([1, 3], res)
    assert_instance_of Integer, res[0]
    assert_instance_of Integer, res[1]
  end

  def test_to_a
    assert_equal([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 1.step(10).to_a)
    assert_equal([1, 3, 5, 7, 9], 1.step(10, 2).to_a)
    assert_equal([1, 3, 5, 7, 9], (1..10).step(2).to_a)
    assert_equal([10, 8, 6, 4, 2], 10.step(1, by: -2).to_a)
    assert_equal([10, 8, 6, 4, 2], (10..1).step(-2).to_a)
    assert_equal([10.0, 8.0, 6.0, 4.0, 2.0], (10.0..1.0).step(-2.0).to_a)
  end

  def test_to_a_bug15444
    seq = ((1/10r)..(1/2r)).step(1/10r)
    assert_num_equal_type([1/10r, 1/5r, 3/10r, 2/5r, 1/2r], seq.to_a,
                          '[ruby-core:90648] [Bug #15444]')
  end

  def test_last_bug17218
    seq = (1.0997r .. 1.1r).step(0.0001r)
    assert_equal([1.0997r, 1.0998r, 1.0999r, 1.1r], seq.to_a, '[ruby-core:100312] [Bug #17218]')
  end

  def test_slice
    seq = 1.step(10, 2)
    assert_equal([[1, 3, 5], [7, 9]], seq.each_slice(3).to_a)

    seq = 10.step(1, -2)
    assert_equal([[10, 8, 6], [4, 2]], seq.each_slice(3).to_a)
  end

  def test_cons
    seq = 1.step(10, 2)
    assert_equal([[1, 3, 5], [3, 5, 7], [5, 7, 9]], seq.each_cons(3).to_a)

    seq = 10.step(1, -2)
    assert_equal([[10, 8, 6], [8, 6, 4], [6, 4, 2]], seq.each_cons(3).to_a)
  end

  def test_with_index
    seq = 1.step(6, 2)
    assert_equal([[1, 0], [3, 1], [5, 2]], seq.with_index.to_a)
    assert_equal([[1, 10], [3, 11], [5, 12]], seq.with_index(10).to_a)

    seq = 10.step(5, -2)
    assert_equal([[10, 0], [8, 1], [6, 2]], seq.with_index.to_a)
    assert_equal([[10, 10], [8, 11], [6, 12]], seq.with_index(10).to_a)
  end

  def test_with_object
    obj = [0, 1]
    seq = 1.step(10, 2)
    ret = seq.each_with_object(obj) do |i, memo|
      memo[0] += i
      memo[1] *= i
    end
    assert_same(obj, ret)
    assert_equal([25, 945], ret)

    obj = [0, 1]
    seq = 10.step(1, -2)
    ret = seq.each_with_object(obj) do |i, memo|
      memo[0] += i
      memo[1] *= i
    end
    assert_same(obj, ret)
    assert_equal([30, 3840], ret)
  end

  def test_next
    seq = 1.step(10, 2)
    [1, 3, 5, 7, 9].each do |i|
      assert_equal(i, seq.next)
    end

    seq = 10.step(1, -2)
    [10, 8, 6, 4, 2].each do |i|
      assert_equal(i, seq.next)
    end

    seq = ((1/10r)..(1/2r)).step(0)
    assert_equal(1/10r, seq.next)
  end

  def test_next_bug15444
    seq = ((1/10r)..(1/2r)).step(1/10r)
    assert_equal(1/10r, seq.next, '[ruby-core:90648] [Bug #15444]')
  end

  def test_next_rewind
    seq = 1.step(6, 2)
    assert_equal(1, seq.next)
    assert_equal(3, seq.next)
    seq.rewind
    assert_equal(1, seq.next)
    assert_equal(3, seq.next)
    assert_equal(5, seq.next)
    assert_raise(StopIteration) { seq.next }

    seq = 10.step(5, -2)
    assert_equal(10, seq.next)
    assert_equal(8, seq.next)
    seq.rewind
    assert_equal(10, seq.next)
    assert_equal(8, seq.next)
    assert_equal(6, seq.next)
    assert_raise(StopIteration) { seq.next }
  end

  def test_next_after_stopiteration
    seq = 1.step(2, 2)
    assert_equal(1, seq.next)
    assert_raise(StopIteration) { seq.next }
    assert_raise(StopIteration) { seq.next }
    seq.rewind
    assert_equal(1, seq.next)
    assert_raise(StopIteration) { seq.next }
    assert_raise(StopIteration) { seq.next }
  end

  def test_stop_result
    seq = 1.step(2, 2)
    res = seq.each {}
    assert_equal(1, seq.next)
    exc = assert_raise(StopIteration) { seq.next }
    assert_equal(res, exc.result)
  end

  def test_peek
    seq = 1.step(2, 2)
    assert_equal(1, seq.peek)
    assert_equal(1, seq.peek)
    assert_equal(1, seq.next)
    assert_raise(StopIteration) { seq.peek }
    assert_raise(StopIteration) { seq.peek }

    seq = 10.step(9, -2)
    assert_equal(10, seq.peek)
    assert_equal(10, seq.peek)
    assert_equal(10, seq.next)
    assert_raise(StopIteration) { seq.peek }
    assert_raise(StopIteration) { seq.peek }
  end

  def test_next_values
    seq = 1.step(2, 2)
    assert_equal([1], seq.next_values)
  end

  def test_peek_values
    seq = 1.step(2, 2)
    assert_equal([1], seq.peek_values)
  end

  def test_num_step_inspect
    assert_equal('(1.step)', 1.step.inspect)
    assert_equal('(1.step(10))', 1.step(10).inspect)
    assert_equal('(1.step(10, 2))', 1.step(10, 2).inspect)
    assert_equal('(1.step(10, by: 2))', 1.step(10, by: 2).inspect)
    assert_equal('(1.step(by: 2))', 1.step(by: 2).inspect)
  end

  def test_range_step_inspect
    assert_equal('((1..).step)', (1..).step.inspect)
    assert_equal('((1..10).step)', (1..10).step.inspect)
    assert_equal('((1..10).step(2))', (1..10).step(2).inspect)
  end

  def test_num_step_size
    assert_equal(10, 1.step(10).size)
    assert_equal(5, 1.step(10, 2).size)
    assert_equal(4, 1.step(10, 3).size)
    assert_equal(1, 1.step(10, 10).size)
    assert_equal(0, 1.step(0).size)
    assert_equal(Float::INFINITY, 1.step.size)

    assert_equal(10, 10.step(1, -1).size)
    assert_equal(5, 10.step(1, -2).size)
    assert_equal(4, 10.step(1, -3).size)
    assert_equal(1, 10.step(1, -10).size)
    assert_equal(0, 1.step(2, -1).size)
    assert_equal(Float::INFINITY, 1.step(by: -1).size)
  end

  def test_range_step_size
    assert_equal(10, (1..10).step.size)
    assert_equal(9, (1...10).step.size)
    assert_equal(5, (1..10).step(2).size)
    assert_equal(5, (1...10).step(2).size)
    assert_equal(4, (1...9).step(2).size)
    assert_equal(Float::INFINITY, (1..).step.size)

    assert_equal(10, (10..1).step(-1).size)
    assert_equal(9, (10...1).step(-1).size)
    assert_equal(5, (10..1).step(-2).size)
    assert_equal(5, (10...1).step(-2).size)
    assert_equal(4, (10...2).step(-2).size)
    assert_equal(Float::INFINITY, (1..).step(-1).size)
  end

  def assert_num_equal_type(ary1, ary2, message=nil)
    assert_equal(ary1.length, ary2.length, message)
    ary1.zip(ary2) do |e1, e2|
      assert_equal(e1.class, e2.class, message)
      if e1.is_a? Complex
        assert_equal(e1.real, e2.real, message)
        assert_equal(e1.imag, e2.imag, message)
      else
        assert_equal(e1, e2, message)
      end
    end
  end

  def test_complex
    assert_num_equal_type([1, 1+1i, 1+2i], (1..).step(1i).take(3))
    assert_num_equal_type([1, 1+1.0i, 1+2.0i], (1..).step(1.0i).take(3))
    assert_num_equal_type([0.0, 0.0+1.0i, 0.0+2.0i], (0.0..).step(1.0i).take(3))
    assert_num_equal_type([0.0+0.0i, 0.0+1.0i, 0.0+2.0i], (0.0i..).step(1.0i).take(3))
  end

  def test_sum
    assert_equal([1, 3, 5, 7, 9].sum, (1..10).step(2).sum)
    assert_equal([1.0, 2.5, 4.0, 5.5, 7.0, 8.5, 10.0].sum, (1.0..10.0).step(1.5).sum)
    assert_equal([1/2r, 1r, 3/2r, 2, 5/2r, 3, 7/2r, 4].sum, ((1/2r)...(9/2r)).step(1/2r).sum)
  end
end
