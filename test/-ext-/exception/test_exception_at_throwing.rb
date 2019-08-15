# frozen_string_literal: true
require 'test/unit'

module Bug
  class Test_ExceptionAT < Test::Unit::TestCase
    def test_exception_at_throwing
      assert_separately(%w[-r-test-/exception], "#{<<-"begin;"}\n#{<<-"end;"}")
      begin;
        e = RuntimeError.new("[Bug #13176]")
        assert_raise_with_message(e.class, e.message) do
          catch do |t|
            Bug::Exception.ensure_raise(nil, e) {throw t}
          end
        end
      end;
    end
  end
end
