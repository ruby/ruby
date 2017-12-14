require_relative 'helper'

module DTrace
  class TestMethodCacheClear < TestCase
    def test_method_cache_clear
      trap_probe(probe, <<-code) do |_,rbfile,lines|
        class String; end
        class String; def abc() end end
        class Object; def abc() end end
      code
        assert_not_includes lines, "String #{rbfile} 1\n"
        assert_includes     lines, "String #{rbfile} 2\n"
        assert_includes     lines, "global #{rbfile} 3\n"
      end
    end

    private
    def probe
      <<-eoprobe
ruby$target:::method-cache-clear
/arg1/
{
  printf("%s %s %d\\n", copyinstr(arg0), copyinstr(arg1), arg2);
}
      eoprobe
    end
  end
end if defined?(DTrace::TestCase)
