require_relative 'helper'
require "reline/history"

class Reline::History::Test < Reline::TestCase
  def test_ancestors
    assert_equal(Reline::History.ancestors.include?(Array), true)
  end

  def test_to_s
    history = history_new
    expected = "HISTORY"
    assert_equal(expected, history.to_s)
  end

  def test_get
    history, lines = lines = history_new_and_push_history(5)
    lines.each_with_index do |s, i|
      assert_external_string_equal(s, history[i])
    end
  end

  def test_get__negative
    history, lines = lines = history_new_and_push_history(5)
    (1..5).each do |i|
      assert_equal(lines[-i], history[-i])
    end
  end

  def test_get__out_of_range
    history, _ = history_new_and_push_history(5)
    invalid_indexes = [5, 6, 100, -6, -7, -100]
    invalid_indexes.each do |i|
      assert_raise(IndexError, "i=<#{i}>") do
        history[i]
      end
    end

    invalid_indexes = [100_000_000_000_000_000_000,
                       -100_000_000_000_000_000_000]
    invalid_indexes.each do |i|
      assert_raise(RangeError, "i=<#{i}>") do
        history[i]
      end
    end
  end

  def test_set
    begin
      history, _ = history_new_and_push_history(5)
      5.times do |i|
        expected = "set: #{i}"
        history[i] = expected
        assert_external_string_equal(expected, history[i])
      end
    rescue NotImplementedError
    end
  end

  def test_set__out_of_range
    history = history_new
    assert_raise(IndexError, NotImplementedError, "index=<0>") do
      history[0] = "set: 0"
    end

    history, _ = history_new_and_push_history(5)
    invalid_indexes = [5, 6, 100, -6, -7, -100]
    invalid_indexes.each do |i|
      assert_raise(IndexError, NotImplementedError, "index=<#{i}>") do
        history[i] = "set: #{i}"
      end
    end

    invalid_indexes = [100_000_000_000_000_000_000,
                       -100_000_000_000_000_000_000]
    invalid_indexes.each do |i|
      assert_raise(RangeError, NotImplementedError, "index=<#{i}>") do
        history[i] = "set: #{i}"
      end
    end
  end

  def test_push
    history = history_new
    5.times do |i|
      s = i.to_s
      assert_equal(history, history.push(s))
      assert_external_string_equal(s, history[i])
    end
    assert_equal(5, history.length)
  end

  def test_push__operator
    history = history_new
    5.times do |i|
      s = i.to_s
      assert_equal(history, history << s)
      assert_external_string_equal(s, history[i])
    end
    assert_equal(5, history.length)
  end

  def test_push__plural
    history = history_new
    assert_equal(history, history.push("0", "1", "2", "3", "4"))
    (0..4).each do |i|
      assert_external_string_equal(i.to_s, history[i])
    end
    assert_equal(5, history.length)

    assert_equal(history, history.push("5", "6", "7", "8", "9"))
    (5..9).each do |i|
      assert_external_string_equal(i.to_s, history[i])
    end
    assert_equal(10, history.length)
  end

  def test_pop
    history = history_new
    begin
      assert_equal(nil, history.pop)

      history, lines = lines = history_new_and_push_history(5)
      (1..5).each do |i|
        assert_external_string_equal(lines[-i], history.pop)
        assert_equal(lines.length - i, history.length)
      end

      assert_equal(nil, history.pop)
    rescue NotImplementedError
    end
  end

  def test_shift
    history = history_new
    begin
      assert_equal(nil, history.shift)

      history, lines = lines = history_new_and_push_history(5)
      (0..4).each do |i|
        assert_external_string_equal(lines[i], history.shift)
        assert_equal(lines.length - (i + 1), history.length)
      end

      assert_equal(nil, history.shift)
    rescue NotImplementedError
    end
  end

  def test_each
    history = history_new
    e = history.each do |s|
      assert(false) # not reachable
    end
    assert_equal(history, e)
    history, lines = lines = history_new_and_push_history(5)
    i = 0
    e = history.each do |s|
      assert_external_string_equal(history[i], s)
      assert_external_string_equal(lines[i], s)
      i += 1
    end
    assert_equal(history, e)
  end

  def test_each__enumerator
    history = history_new
    e = history.each
    assert_instance_of(Enumerator, e)
  end

  def test_length
    history = history_new
    assert_equal(0, history.length)
    push_history(history, 1)
    assert_equal(1, history.length)
    push_history(history, 4)
    assert_equal(5, history.length)
    history.clear
    assert_equal(0, history.length)
  end

  def test_empty_p
    history = history_new
    2.times do
      assert(history.empty?)
      history.push("s")
      assert_equal(false, history.empty?)
      history.clear
      assert(history.empty?)
    end
  end

  def test_delete_at
    begin
      history, lines = lines = history_new_and_push_history(5)
      (0..4).each do |i|
        assert_external_string_equal(lines[i], history.delete_at(0))
      end
      assert(history.empty?)

      history, lines = lines = history_new_and_push_history(5)
      (1..5).each do |i|
        assert_external_string_equal(lines[lines.length - i], history.delete_at(-1))
      end
      assert(history.empty?)

      history, lines = lines = history_new_and_push_history(5)
      assert_external_string_equal(lines[0], history.delete_at(0))
      assert_external_string_equal(lines[4], history.delete_at(3))
      assert_external_string_equal(lines[1], history.delete_at(0))
      assert_external_string_equal(lines[3], history.delete_at(1))
      assert_external_string_equal(lines[2], history.delete_at(0))
      assert(history.empty?)
    rescue NotImplementedError
    end
  end

  def test_delete_at__out_of_range
    history = history_new
    assert_raise(IndexError, NotImplementedError, "index=<0>") do
      history.delete_at(0)
    end

    history, _ = history_new_and_push_history(5)
    invalid_indexes = [5, 6, 100, -6, -7, -100]
    invalid_indexes.each do |i|
      assert_raise(IndexError, NotImplementedError, "index=<#{i}>") do
        history.delete_at(i)
      end
    end

    invalid_indexes = [100_000_000_000_000_000_000,
                       -100_000_000_000_000_000_000]
    invalid_indexes.each do |i|
      assert_raise(RangeError, NotImplementedError, "index=<#{i}>") do
        history.delete_at(i)
      end
    end
  end

  private

  def history_new(history_size: 10)
    Reline::History.new(Struct.new(:history_size).new(history_size))
  end

  def push_history(history, num)
    lines = []
    num.times do |i|
      s = "a"
      i.times do
        s = s.succ
      end
      lines.push("#{i + 1}:#{s}")
    end
    history.push(*lines)
    return history, lines
  end

  def history_new_and_push_history(num)
    history = history_new(history_size: 100)
    return push_history(history, num)
  end

  def assert_external_string_equal(expected, actual)
    assert_equal(expected, actual)
    assert_equal(get_default_internal_encoding, actual.encoding)
  end

  def get_default_internal_encoding
    return Encoding.default_internal || Encoding.find("locale")
  end
end
