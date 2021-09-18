# frozen_string_literal: false
require 'test/unit'

class TestTestUnitSorting < Test::Unit::TestCase
  def test_sorting
    result = sorting("--show-skip")
    assert_match(/^  1\) Skipped:/, result)
    assert_match(/^  2\) Failure:/, result)
    assert_match(/^  3\) Error:/,   result)
  end

  def sorting(*args)
    IO.popen([*@options[:ruby], "#{File.dirname(__FILE__)}/test4test_sorting.rb",
              "--verbose", *args], err: [:child, :out]) {|f|
      f.read
    }
  end

  Item = Struct.new(:name)
  SEED = 0x50975eed

  def make_test_list
    (1..16).map {"test_%.3x" % rand(0x1000)}.freeze
  end

  def test_sort_alpha
    sorter = Test::Unit::Order::Types[:alpha].new(SEED)
    assert_kind_of(Test::Unit::Order::Types[:sorted], sorter)

    list = make_test_list
    sorted = list.sort
    16.times do
      assert_equal(sorted, sorter.sort_by_string(list))
    end

    list = list.map {|s| Item.new(s)}.freeze
    sorted = list.sort_by(&:name)
    16.times do
      assert_equal(sorted, sorter.sort_by_name(list))
    end
  end

  def test_sort_nosort
    sorter = Test::Unit::Order::Types[:nosort].new(SEED)

    list = make_test_list
    16.times do
      assert_equal(list, sorter.sort_by_string(list))
    end

    list = list.map {|s| Item.new(s)}.freeze
    16.times do
      assert_equal(list, sorter.sort_by_name(list))
    end
  end

  def test_sort_random
    type = Test::Unit::Order::Types[:random]
    sorter = type.new(SEED)

    list = make_test_list
    sorted = type.new(SEED).sort_by_string(list).freeze
    16.times do
      assert_equal(sorted, sorter.sort_by_string(list))
    end
    assert_not_equal(sorted, type.new(SEED+1).sort_by_string(list))

    list = list.map {|s| Item.new(s)}.freeze
    sorted = sorted.map {|s| Item.new(s)}.freeze
    16.times do
      assert_equal(sorted, sorter.sort_by_name(list))
    end
    assert_not_equal(sorted, type.new(SEED+1).sort_by_name(list))
  end
end
