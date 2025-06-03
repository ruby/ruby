# frozen_string_literal: true
require 'test/unit'
require 'rbconfig'

class TestIOConsoleInRactor < Test::Unit::TestCase
  def test_ractor
    ext = "/io/console.#{RbConfig::CONFIG['DLEXT']}"
    path = $".find {|path| path.end_with?(ext)}
    assert_in_out_err(%W[-r#{path}], "#{<<~"begin;"}\n#{<<~'end;'}", ["true"], [])
    begin;
      class Ractor
        alias value take
      end unless Ractor.method_defined? :value # compat with Ruby 3.4 and olders

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
      puts r.value
    end;

    assert_in_out_err(%W[-r#{path}], "#{<<~"begin;"}\n#{<<~'end;'}", ["true"], [])
    begin;
      class Ractor
        alias value take
      end unless Ractor.method_defined? :value # compat with Ruby 3.4 and olders

      console = IO.console
      $VERBOSE = nil
      r = Ractor.new do
        IO.console
      end
      puts console.class == r.value.class
    end;
  end
end if defined? Ractor
