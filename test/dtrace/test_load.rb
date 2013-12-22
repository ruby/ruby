require_relative 'helper'
require 'tempfile'

module DTrace
  class TestLoad < TestCase
    def setup
      super
      @rbfile = Tempfile.new(['omg', 'rb'])
      @rbfile.write 'x = 10'
    end

    def teardown
      super
      @rbfile.close(true) if @rbfile
    end

    def test_load_entry
      probe = <<-eoprobe
ruby$target:::load-entry
{
  printf("%s %s %d\\n", copyinstr(arg0), copyinstr(arg1), arg2);
}
      eoprobe
      trap_probe(probe, program) { |dpath, rbpath, saw|
	saw = saw.map(&:split).find_all { |loaded, _, _|
	  loaded == @rbfile.path
	}
	assert_equal 10, saw.length
      }
    end

    def test_load_return
      probe = <<-eoprobe
ruby$target:::load-return
{
  printf("%s\\n", copyinstr(arg0));
}
      eoprobe
      trap_probe(probe, program) { |dpath, rbpath, saw|
	saw = saw.map(&:split).find_all { |loaded, _, _|
	  loaded == @rbfile.path
	}
	assert_equal 10, saw.length
      }
    end

    private
    def program
      "10.times { load '#{@rbfile.path}' }"
    end
  end
end if defined?(DTrace::TestCase)
