# frozen_string_literal: false
require 'test/unit'

class TestHideSkip < Test::Unit::TestCase
  def test_hideskip
    assert_not_match(/^ *1\) Skipped/, hideskip)
    assert_match(/^ *1\) Skipped.*^ *2\) Skipped/m, hideskip("--show-skip"))
    output = hideskip("--hide-skip")
    output.gsub!(/Successful RJIT finish\n/, '') if defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled?
    assert_match(/assertions\/s.\n+2 tests, 0 assertions, 0 failures, 0 errors, 2 skips/, output)
  end

  private

  def hideskip(*args)
    IO.popen([*@__runner_options__[:ruby], "#{File.dirname(__FILE__)}/test4test_hideskip.rb",
                       "--verbose", *args], err: [:child, :out]) {|f|
      f.read
    }
  end
end
