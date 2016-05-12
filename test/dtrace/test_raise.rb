# frozen_string_literal: false
require_relative 'helper'

module DTrace
  class TestRaise < TestCase
    def test_raise
      probe = <<-eoprobe
ruby$target:::raise
{
  printf("%s %s %d\\n", copyinstr(arg0), copyinstr(arg1), arg2);
}
      eoprobe
      trap_probe(probe, program) { |dpath, rbpath, saw|
	saw = saw.map(&:split).find_all { |_, source_file, _|
	  source_file == rbpath
	}
	assert_equal 10, saw.length
	saw.each do |klass, _, source_line|
	  assert_equal 'RuntimeError', klass
	  assert_equal '1', source_line
	end
      }
    end

    private
    def program
      '10.times { raise rescue nil }'
    end
  end
end if defined?(DTrace::TestCase)
