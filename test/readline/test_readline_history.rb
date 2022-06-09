# frozen_string_literal: false
require_relative "helper"
require "test/unit"

module BasetestReadlineHistory
  def setup
    Readline::HISTORY.clear
  end

  def test_to_s
    expected = "HISTORY"
    assert_equal(expected, Readline::HISTORY.to_s)
  end

  def test_get
    lines = push_history(5)
    lines.each_with_index do |s, i|
      assert_external_string_equal(s, Readline::HISTORY[i])
    end
  end

  def test_get__negative
    lines = push_history(5)
    (1..5).each do |i|
      assert_equal(lines[-i], Readline::HISTORY[-i])
    end
  end

  def test_get__out_of_range
    push_history(5)
    invalid_indexes = [5, 6, 100, -6, -7, -100]
    invalid_indexes.each do |i|
      assert_raise(IndexError, "i=<#{i}>") do
        Readline::HISTORY[i]
      end
    end

    invalid_indexes = [100_000_000_000_000_000_000,
                       -100_000_000_000_000_000_000]
    invalid_indexes.each do |i|
      assert_raise(RangeError, "i=<#{i}>") do
        Readline::HISTORY[i]
      end
    end
  end

  def test_set
    begin
      push_history(5)
      5.times do |i|
        expected = "set: #{i}"
        Readline::HISTORY[i] = expected
        assert_external_string_equal(expected, Readline::HISTORY[i])
      end
    rescue NotImplementedError
    end
  end

  def test_set__out_of_range
    assert_raise(IndexError, NotImplementedError, "index=<0>") do
      Readline::HISTORY[0] = "set: 0"
    end

    push_history(5)
    invalid_indexes = [5, 6, 100, -6, -7, -100]
    invalid_indexes.each do |i|
      assert_raise(IndexError, NotImplementedError, "index=<#{i}>") do
        Readline::HISTORY[i] = "set: #{i}"
      end
    end

    invalid_indexes = [100_000_000_000_000_000_000,
                       -100_000_000_000_000_000_000]
    invalid_indexes.each do |i|
      assert_raise(RangeError, NotImplementedError, "index=<#{i}>") do
        Readline::HISTORY[i] = "set: #{i}"
      end
    end
  end

  def test_push
    5.times do |i|
      s = i.to_s
      assert_equal(Readline::HISTORY, Readline::HISTORY.push(s))
      assert_external_string_equal(s, Readline::HISTORY[i])
    end
    assert_equal(5, Readline::HISTORY.length)
  end

  def test_push__operator
    5.times do |i|
      s = i.to_s
      assert_equal(Readline::HISTORY, Readline::HISTORY << s)
      assert_external_string_equal(s, Readline::HISTORY[i])
    end
    assert_equal(5, Readline::HISTORY.length)
  end

  def test_push__plural
    assert_equal(Readline::HISTORY, Readline::HISTORY.push("0", "1", "2", "3", "4"))
    (0..4).each do |i|
      assert_external_string_equal(i.to_s, Readline::HISTORY[i])
    end
    assert_equal(5, Readline::HISTORY.length)

    assert_equal(Readline::HISTORY, Readline::HISTORY.push("5", "6", "7", "8", "9"))
    (5..9).each do |i|
      assert_external_string_equal(i.to_s, Readline::HISTORY[i])
    end
    assert_equal(10, Readline::HISTORY.length)
  end

  def test_pop
    begin
      assert_equal(nil, Readline::HISTORY.pop)

      lines = push_history(5)
      (1..5).each do |i|
        assert_external_string_equal(lines[-i], Readline::HISTORY.pop)
        assert_equal(lines.length - i, Readline::HISTORY.length)
      end

      assert_equal(nil, Readline::HISTORY.pop)
    rescue NotImplementedError
    end
  end

  def test_shift
    begin
      assert_equal(nil, Readline::HISTORY.shift)

      lines = push_history(5)
      (0..4).each do |i|
        assert_external_string_equal(lines[i], Readline::HISTORY.shift)
        assert_equal(lines.length - (i + 1), Readline::HISTORY.length)
      end

      assert_equal(nil, Readline::HISTORY.shift)
    rescue NotImplementedError
    end
  end

  def test_each
    e = Readline::HISTORY.each do |s|
      assert(false) # not reachable
    end
    assert_equal(Readline::HISTORY, e)
    lines = push_history(5)
    i = 0
    e = Readline::HISTORY.each do |s|
      assert_external_string_equal(Readline::HISTORY[i], s)
      assert_external_string_equal(lines[i], s)
      i += 1
    end
    assert_equal(Readline::HISTORY, e)
  end

  def test_each__enumerator
    e = Readline::HISTORY.each
    assert_instance_of(Enumerator, e)
  end

  def test_length
    assert_equal(0, Readline::HISTORY.length)
    push_history(1)
    assert_equal(1, Readline::HISTORY.length)
    push_history(4)
    assert_equal(5, Readline::HISTORY.length)
    Readline::HISTORY.clear
    assert_equal(0, Readline::HISTORY.length)
  end

  def test_empty_p
    2.times do
      assert(Readline::HISTORY.empty?)
      Readline::HISTORY.push("s")
      assert_equal(false, Readline::HISTORY.empty?)
      Readline::HISTORY.clear
      assert(Readline::HISTORY.empty?)
    end
  end

  def test_delete_at
    begin
      lines = push_history(5)
      (0..4).each do |i|
        assert_external_string_equal(lines[i], Readline::HISTORY.delete_at(0))
      end
      assert(Readline::HISTORY.empty?)

      lines = push_history(5)
      (1..5).each do |i|
        assert_external_string_equal(lines[lines.length - i], Readline::HISTORY.delete_at(-1))
      end
      assert(Readline::HISTORY.empty?)

      lines = push_history(5)
      assert_external_string_equal(lines[0], Readline::HISTORY.delete_at(0))
      assert_external_string_equal(lines[4], Readline::HISTORY.delete_at(3))
      assert_external_string_equal(lines[1], Readline::HISTORY.delete_at(0))
      assert_external_string_equal(lines[3], Readline::HISTORY.delete_at(1))
      assert_external_string_equal(lines[2], Readline::HISTORY.delete_at(0))
      assert(Readline::HISTORY.empty?)
    rescue NotImplementedError
    end
  end

  def test_delete_at__out_of_range
    assert_raise(IndexError, NotImplementedError, "index=<0>") do
      Readline::HISTORY.delete_at(0)
    end

    push_history(5)
    invalid_indexes = [5, 6, 100, -6, -7, -100]
    invalid_indexes.each do |i|
      assert_raise(IndexError, NotImplementedError, "index=<#{i}>") do
        Readline::HISTORY.delete_at(i)
      end
    end

    invalid_indexes = [100_000_000_000_000_000_000,
                       -100_000_000_000_000_000_000]
    invalid_indexes.each do |i|
      assert_raise(RangeError, NotImplementedError, "index=<#{i}>") do
        Readline::HISTORY.delete_at(i)
      end
    end
  end

  private

  def push_history(num)
    lines = []
    num.times do |i|
      s = "a"
      i.times do
        s = s.succ
      end
      lines.push("#{i + 1}:#{s}")
    end
    Readline::HISTORY.push(*lines)
    return lines
  end

  def assert_external_string_equal(expected, actual)
    assert_equal(expected, actual)
    assert_equal(get_default_internal_encoding, actual.encoding)
  end

  def get_default_internal_encoding
    return Encoding.default_internal || Encoding.find("locale")
  end
end

class TestReadlineHistory < Test::Unit::TestCase
  include BasetestReadlineHistory

  def setup
    use_ext_readline
    super
  end
end if defined?(::ReadlineSo) && defined?(::ReadlineSo::HISTORY) &&
  ENV["TEST_READLINE_OR_RELINE"] != "Reline" &&
  (
   begin
     ReadlineSo::HISTORY.clear
   rescue NotImplementedError
     false
   end
   )

class TestRelineAsReadlineHistory < Test::Unit::TestCase
  include BasetestReadlineHistory

  def setup
    use_lib_reline
    super
  end

  def teardown
    finish_using_lib_reline
    super
  end

  def get_default_internal_encoding
    if RUBY_PLATFORM =~ /mswin|mingw/
      Encoding.default_internal || Encoding::UTF_8
    else
      Reline::IOGate.encoding
    end
  end
end if defined?(Reline) && ENV["TEST_READLINE_OR_RELINE"] != "Readline"
