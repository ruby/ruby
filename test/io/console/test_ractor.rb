# frozen_string_literal: true
require 'test/unit'
require 'rbconfig'

class TestIOConsoleInRactor < Test::Unit::TestCase
  def test_ractor
    ext = "/io/console.#{RbConfig::CONFIG['DLEXT']}"
    path = $".find {|path| path.end_with?(ext)}
    assert_in_out_err(%W[-r#{path}], "#{<<~"begin;"}\n#{<<~'end;'}", ["true"], [])
    begin;
      $VERBOSE = nil
      r = Ractor.new do
        $stdout.console_mode
      rescue SystemCallError
        true
      rescue Ractor::UnsafeError
        false
      else
        true                    # should not success
      end
      puts r.take
    end;

    assert_in_out_err(%W[-r#{path}], "#{<<~"begin;"}\n#{<<~'end;'}", ["true"], [])
    begin;
      console = IO.console
      $VERBOSE = nil
      r = Ractor.new do
        IO.console
      end
      puts console.class == r.take.class
    end;
  end
end if defined? Ractor
