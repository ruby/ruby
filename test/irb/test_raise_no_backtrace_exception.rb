# frozen_string_literal: false
require 'test/unit'

module TestIRB
  class TestRaiseNoBacktraceException < Test::Unit::TestCase
    def test_raise_exception
      bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
      assert_in_out_err(bundle_exec + %w[-rirb -W0 -e IRB.start(__FILE__) -- -f --], <<-IRB, /Exception: foo/, [])
      e = Exception.new("foo")
      puts e.inspect
      def e.backtrace; nil; end
      raise e
IRB
    end
  end
end
