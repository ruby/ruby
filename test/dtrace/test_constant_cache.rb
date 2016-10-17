# frozen_string_literal: false
require_relative 'helper'

module DTrace
  class TestConstantCacheClear < TestCase
    def test_constant_cache_clear
      trap_probe(probe, code) do |_,rbfile,lines|
        assert_not_include lines, "#{rbfile} 1\n"
        assert_include     lines, "#{rbfile} 2\n"
        assert_include     lines, "#{rbfile} 3\n"
      end
    end

    private
    def probe
      <<-eoprobe
        ruby$target:::constant-cache-clear
        /arg1/
        {
          printf("%s %d\\n", copyinstr(arg0), arg1);
        }
      eoprobe
    end

    def code
      <<-code
        class String; end
        class NewClass; end
        NEW_CONSTANT = ''
      code
    end
  end
end if defined?(DTrace::TestCase)
