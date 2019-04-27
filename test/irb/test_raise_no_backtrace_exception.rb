# frozen_string_literal: false
require 'test/unit'

module TestIRB
  class TestRaiseNoBacktraceException < Test::Unit::TestCase
    def test_raise_exception
      assert_in_out_err(%w[-rirb -W0 -e IRB.start(__FILE__) -- -f --], <<-IRB, /Exception: foo/, [])
      e = Exception.new("foo")
      def e.backtrace; nil; end
      raise e
IRB
    end
  end
end
