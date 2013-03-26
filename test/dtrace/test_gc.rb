require_relative 'helper'

module DTrace
  class TestGC < TestCase
    %w{
      gc-mark-begin
      gc-mark-end
      gc-sweep-begin
      gc-sweep-end
    }.each do |probe_name|
      define_method(:"test_#{probe_name.gsub(/-/, '_')}") do
	probe = "ruby$target:::#{probe_name} { printf(\"#{probe_name}\\n\"); }"

	trap_probe(probe, ruby_program) { |_, _, saw|
	  assert_operator saw.length, :>, 0
	}

      end
    end

    private
    def ruby_program
      "100000.times { Object.new }"
    end
  end
end if defined?(DTrace::TestCase)
