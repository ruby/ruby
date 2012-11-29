require File.expand_path('../helper', __FILE__)
require 'stringio'

class TestTraceOutput < Rake::TestCase
  include Rake::TraceOutput

  class PrintSpy
    attr_reader :result, :calls
    def initialize
      @result = ""
      @calls = 0
    end
    def print(string)
      @result << string
      @calls += 1
    end
  end

  def test_trace_issues_single_io_for_args_with_empty_args
    spy = PrintSpy.new
    trace_on(spy)
    assert_equal "\n", spy.result
    assert_equal 1, spy.calls
  end

  def test_trace_issues_single_io_for_args_multiple_strings
    spy = PrintSpy.new
    trace_on(spy, "HI\n", "LO")
    assert_equal "HI\nLO\n", spy.result
    assert_equal 1, spy.calls
  end

  def test_trace_issues_single_io_for_args_multiple_strings_and_alternate_sep
    old_sep = $\
    $\ = "\r"
    spy = PrintSpy.new
    trace_on(spy, "HI\r", "LO")
    assert_equal "HI\rLO\r", spy.result
    assert_equal 1, spy.calls
  ensure
    $\ = old_sep
  end
end
