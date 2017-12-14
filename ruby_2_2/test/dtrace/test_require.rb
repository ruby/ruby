require_relative 'helper'

module DTrace
  class TestRequire < TestCase
    def test_require_entry
      probe = <<-eoprobe
ruby$target:::require-entry
{
  printf("%s %s %d\\n", copyinstr(arg0), copyinstr(arg1), arg2);
}
      eoprobe
      trap_probe(probe, ruby_program) { |d_file, rb_file, saw|
	required = saw.map { |s| s.split }.find_all do |(required, _)|
	  required == 'dtrace/dummy'
	end
	assert_equal 10, required.length
      }
    end

    def test_require_return
      probe = <<-eoprobe
ruby$target:::require-return
{
  printf("%s\\n", copyinstr(arg0));
}
      eoprobe
    end

    private
    def ruby_program
      "10.times { require 'dtrace/dummy' }"
    end
  end
end if defined?(DTrace::TestCase)
