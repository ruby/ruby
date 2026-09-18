# frozen_string_literal: true

require_relative "test_helper"

# There have also been changes made in other versions of Ruby, so we only want
# to test on the most recent versions.
return if !defined?(RubyVM::InstructionSequence) || RUBY_VERSION < "3.4.0"

module Prism
  class NewlineTest < TestCase
    # If you are coming from ruby/ruby, a test failure here means that TracePoint `:line` events changed.
    # Before adding a skip, make sure that you actually intended for such a difference to happen.
    base = __dir__
    Dir["{,api/,encoding/,result/,ruby/}*.rb", base: base].each do |relative|
      define_method(:"test_#{relative}") do
        assert_newlines(base, relative)
      end
    end

    private

    def assert_newlines(base, relative)
      filepath = File.join(base, relative)
      source = File.read(filepath, binmode: true, external_encoding: Encoding::UTF_8)
      expected = rubyvm_lines(source)

      result = Prism.parse_file(filepath)
      assert_empty result.errors
      actual = prism_lines(result)

      assert_equal expected, actual
    end

    def rubyvm_lines(source)
      queue = [ignore_warnings { RubyVM::InstructionSequence.compile(source) }]
      lines = []

      while iseq = queue.shift
        lines.concat(iseq.trace_points.filter_map { |line, event| line if event == :line })
        iseq.each_child { |insn| queue << insn unless insn.label.start_with?("ensure in ") }
      end

      lines.sort
    end

    def prism_lines(result)
      result.mark_newlines!

      queue = [result.value]
      newlines = []

      while node = queue.shift
        queue.concat(node.compact_child_nodes)
        newlines << result.source.line(node.location.start_offset) if node&.newline_flag?
      end

      newlines.sort
    end
  end
end
