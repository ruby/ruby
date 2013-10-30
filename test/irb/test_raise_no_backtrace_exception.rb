require 'test/unit'
require_relative '../ruby/envutil'

module TestIRB
  class TestRaiseNoBacktraceException < Test::Unit::TestCase
    def test_raise_exception
      status = assert_in_out_err(%w[-rirb -e IRB.start(__FILE__) -- -f --], <<-IRB, /Exception: foo/, [])
      e = Exception.new("foo")
      def e.backtrace; nil; end
      raise e
IRB
    end
  end
end
