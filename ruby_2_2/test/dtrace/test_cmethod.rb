require_relative 'helper'

module DTrace
  class TestCMethod < TestCase
    def test_entry
      probe = <<-eoprobe
ruby$target:::cmethod-entry
{
  printf("%s %s %s %d\\n", copyinstr(arg0), copyinstr(arg1), copyinstr(arg2), arg3);
}
      eoprobe

      trap_probe(probe, ruby_program) { |d_file, rb_file, probes|
	foo_calls = probes.map { |line| line.split }.find_all { |row|
	  row[1] == 'times'
	}

	assert_equal 1, foo_calls.length
      }
    end

    def test_exit
      probe = <<-eoprobe
ruby$target:::cmethod-return
{
  printf("%s %s %s %d\\n", copyinstr(arg0), copyinstr(arg1), copyinstr(arg2), arg3);
}
      eoprobe

      trap_probe(probe, ruby_program) { |d_file, rb_file, probes|
	foo_calls = probes.map { |line| line.split }.find_all { |row|
	  row[1] == 'times'
	}

	assert_equal 1, foo_calls.length
      }
    end

    def ruby_program
      <<-eoruby
      class Foo
	def self.foo; end
      end
      10.times { Foo.foo }
      eoruby
    end
  end
end if defined?(DTrace::TestCase)

