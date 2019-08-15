# frozen_string_literal: false
require 'test/unit'

class TestHideSkip < Test::Unit::TestCase
  def test_hideskip
    assert_not_match(/^ *1\) Skipped/, hideskip)
    assert_match(/^ *1\) Skipped/, hideskip("--show-skip"))
    output = hideskip("--hide-skip")
    output.gsub!(/Successful MJIT finish\n/, '') if RubyVM::MJIT.enabled?
    assert_match(/assertions\/s.\n+1 tests, 0 assertions, 0 failures, 0 errors, 1 skips/, output)
  end

  private

  def hideskip(*args)
    IO.popen([*@options[:ruby], "#{File.dirname(__FILE__)}/test4test_hideskip.rb",
                       "--verbose", *args], err: [:child, :out]) {|f|
      f.read
    }
  end
end
