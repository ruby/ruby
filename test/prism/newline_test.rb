# frozen_string_literal: true

require_relative "test_helper"

return unless defined?(RubyVM::InstructionSequence)

module Prism
  class NewlineTest < TestCase
    skips = %w[
      errors_test.rb
      locals_test.rb
      regexp_test.rb
      test_helper.rb
      unescape_test.rb
      encoding/regular_expression_encoding_test.rb
      encoding/string_encoding_test.rb
      result/static_literals_test.rb
      result/warnings_test.rb
      ruby/parser_test.rb
      ruby/ruby_parser_test.rb
    ]

    base = __dir__
    (Dir["{,api/,encoding/,result/,ruby/}*.rb", base: base] - skips).each do |relative|
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

      source.each_line.with_index(1) do |line, line_number|
        # Lines like `while (foo = bar)` result in two line flags in the
        # bytecode but only one newline flag in the AST. We need to remove the
        # extra line flag from the bytecode to make the test pass.
        if line.match?(/while \(/)
          index = expected.index(line_number)
          expected.delete_at(index) if index
        end

        # Lines like `foo =` where the value is on the next line result in
        # another line flag in the bytecode but only one newline flag in the
        # AST.
        if line.match?(/^\s+\w+ =$/)
          if source.lines[line_number].match?(/^\s+case/)
            actual[actual.index(line_number)] += 1
          else
            actual.delete_at(actual.index(line_number))
          end
        end

        if line.match?(/^\s+\w+ = \[$/)
          if !expected.include?(line_number) && !expected.include?(line_number + 2)
            actual[actual.index(line_number)] += 1
          end
        end
      end

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
        newlines << result.source.line(node.location.start_offset) if node&.newline?
      end

      newlines.sort
    end
  end
end
