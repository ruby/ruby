# frozen_string_literal: false
require 'test/unit'

module TestIRB
  class TestRaiseNoBacktraceException < Test::Unit::TestCase
    def test_raise_exception
      skip if RUBY_ENGINE == 'truffleruby'
      bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
      assert_in_out_err(bundle_exec + %w[-rirb -W0 -e IRB.start(__FILE__) -- -f --], <<-IRB, /Exception: foo/, [])
      e = Exception.new("foo")
      puts e.inspect
      def e.backtrace; nil; end
      raise e
IRB
    end

    def test_raise_exception_with_invalid_byte_sequence
      skip if RUBY_ENGINE == 'truffleruby'
      bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
      assert_in_out_err(bundle_exec + %w[-rirb -W0 -e IRB.start(__FILE__) -- -f --], <<~IRB, /A\\xF3B \(StandardError\)/, [])
        raise StandardError, "A\\xf3B"
      IRB
    end
  end
end
