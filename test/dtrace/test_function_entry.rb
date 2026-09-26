# frozen_string_literal: false
require_relative 'helper'

module DTrace
  class TestFunctionEntry < TestCase
    def test_function_entry
      probe = <<-eoprobe
ruby$target:::method-entry
/arg0 && arg1 && arg2/
{
  printf("%s %s %s %d\\n", copyinstr(arg0), copyinstr(arg1), copyinstr(arg2), arg3);
}
      eoprobe

      trap_probe(probe, ruby_program) { |d_file, rb_file, probes|
	foo_calls = probes.map { |line| line.split }.find_all { |row|
	  row.first == 'Foo'  && row[1] == 'foo'
	}

	assert_equal 10, foo_calls.length, probes
	line = '6'
	foo_calls.each { |f| assert_equal line, f[3] }
	foo_calls.each { |f| assert_equal rb_file, f[2] }
      }
    end

    def test_function_entry_without_trace_point
      probe = <<-eoprobe
ruby$target:::method-entry
/arg0 && arg1 && arg2/
{
  printf("%s %s %s %d\\n", copyinstr(arg0), copyinstr(arg1), copyinstr(arg2), arg3);
}
      eoprobe

      trap_probe(probe, ruby_program_without_trace_point) { |d_file, rb_file, probes|
	foo_calls = probes.map { |line| line.split }.find_all { |row|
	  row.first == 'Foo'  && row[1] == 'foo'
	}

	assert_equal 10, foo_calls.length, probes
	line = '5'
	foo_calls.each { |f| assert_equal line, f[3] }
	foo_calls.each { |f| assert_equal rb_file, f[2] }
      }
    end

    def test_tailcall_function_entry_without_trace_point
      program = <<-eoruby
      code = <<~RUBY
        class Foo
          def foo
            bar
          end

          def bar
            3 + 4
          end
        end

        Foo.new.foo
      RUBY

      RubyVM::InstructionSequence.compile(
        code,
        tailcall_optimization: true,
        trace_instruction: false
      ).eval
      eoruby

      probe = <<-eoprobe
ruby$target:::method-entry
/arg0 && arg1 && arg2/
{
  printf("%s %s %s %d\\n", copyinstr(arg0), copyinstr(arg1), copyinstr(arg2), arg3);
}
      eoprobe

      trap_probe(probe, program) { |d_file, rb_file, probes|
	foo_calls = probes.map { |line| line.split }.find_all { |row|
	  row.first == 'Foo'  && row[1] == 'foo'
	}

	bar_calls = probes.map { |line| line.split }.find_all { |row|
	  row.first == 'Foo'  && row[1] == 'bar'
	}

  assert_equal 1, foo_calls.length, probes
  assert_equal 1, bar_calls.length, probes

  assert_equal '11', foo_calls.first[3]
  assert_equal '<compiled>', foo_calls.first[2]

  assert_equal '11', bar_calls.first[3]
  assert_equal '<compiled>', bar_calls.first[2]
      }
    end

    def test_function_return
      probe = <<-eoprobe
ruby$target:::method-return
/arg0 && arg1 && arg2/
{
  printf("%s %s %s %d\\n", copyinstr(arg0), copyinstr(arg1), copyinstr(arg2), arg3);
}
      eoprobe

      trap_probe(probe, ruby_program) { |d_file, rb_file, probes|
	foo_calls = probes.map { |line| line.split }.find_all { |row|
	  row.first == 'Foo'  && row[1] == 'foo'
	}

	assert_equal 10, foo_calls.length, probes.inspect
	line = '3'
	foo_calls.each { |f| assert_equal line, f[3] }
	foo_calls.each { |f| assert_equal rb_file, f[2] }
      }
    end

    def test_function_return_without_trace_point
      probe = <<-eoprobe
ruby$target:::method-return
/arg0 && arg1 && arg2/
{
  printf("%s %s %s %d\\n", copyinstr(arg0), copyinstr(arg1), copyinstr(arg2), arg3);
}
      eoprobe

      trap_probe(probe, ruby_program_without_trace_point) { |d_file, rb_file, probes|
	foo_calls = probes.map { |line| line.split }.find_all { |row|
	  row.first == 'Foo'  && row[1] == 'foo'
	}

	assert_equal 10, foo_calls.length, probes.inspect
	line = '2'
	foo_calls.each { |f| assert_equal line, f[3] }
	foo_calls.each { |f| assert_equal rb_file, f[2] }
      }
    end

    def test_return_from_raise
      program = <<-eoruby
      class Foo
        def bar; raise; end
        def baz
          bar
        rescue
        end
      end

      Foo.new.baz
      eoruby

      probe = <<-eoprobe
ruby$target:::method-return
/arg0 && arg1 && arg2/
{
  printf("%s %s %s %d\\n", copyinstr(arg0), copyinstr(arg1), copyinstr(arg2), arg3);
}
      eoprobe

      trap_probe(probe, program) { |d_file, rb_file, probes|
	foo_calls = probes.map { |line| line.split }.find_all { |row|
	  row.first == 'Foo'  && row[1] == 'bar'
	}
        assert foo_calls.any?
      }
    end

    private
    def ruby_program
      <<-eoruby
      TracePoint.new{}.__enable(nil, nil, Thread.current)
      class Foo
	def foo; end
      end
      x = Foo.new
      10.times { x.foo }
      eoruby
    end

    def ruby_program_without_trace_point
      <<-eoruby
      class Foo
	def foo; end
      end
      x = Foo.new
      10.times { x.foo }
      eoruby
    end
  end
end if defined?(DTrace::TestCase)
