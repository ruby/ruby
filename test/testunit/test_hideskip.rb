# frozen_string_literal: false
require 'test/unit'

class TestHideSkip < Test::Unit::TestCase
  def test_hideskip
    assert_not_match(/assertions\/s.\n\n  1\) Skipped/, hideskip)
    assert_match(/assertions\/s.\n\n  1\) Skipped/, hideskip("--show-skip"))
    assert_match(/assertions\/s.\n\n1 tests, 0 assertions, 0 failures, 0 errors, 1 skips/, hideskip("--hide-skip"))
  end

  def hideskip(*args)
    IO.popen([*@options[:ruby], "#{File.dirname(__FILE__)}/test4test_hideskip.rb",
                       "--verbose", *args], err: [:child, :out]) {|f|
      f.read
    }
  end
end
