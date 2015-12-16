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
end
