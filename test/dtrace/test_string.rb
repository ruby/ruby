# frozen_string_literal: false
require_relative 'helper'

module DTrace
  class TestStringProbes < TestCase
    def test_object_create_start_string_lit
      trap_probe(probe, '"omglolwutbbq"') { |_,rbfile,saw|
        saw = saw.map(&:split).find_all { |klass, file, line, len|
          file == rbfile && len == '12' && line == '1'
        }
        assert_equal(%w{ String }, saw.map(&:first))
        assert_equal([rbfile], saw.map { |line| line[1] })
        assert_equal(['1'], saw.map { |line| line[2] })
      }
    end

    private
    def probe
      <<-eoprobe
ruby$target:::string-create
/arg1/
{
  printf("String %s %d %d\\n", copyinstr(arg1), arg2, arg0);
}
      eoprobe
    end
  end
end if defined?(DTrace::TestCase)
