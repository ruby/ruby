# frozen_string_literal: true

require "yarp_test_helper"

return unless defined?(RubyVM::InstructionSequence)

# It is useful to have a diff even if the strings to compare are big
# However, ruby/ruby does not have a version of Test::Unit with access to
# max_diff_target_string_size
if defined?(Test::Unit::Assertions::AssertionMessage)
  Test::Unit::Assertions::AssertionMessage.max_diff_target_string_size = 5000
end

class NewlineTest < Test::Unit::TestCase
  class NewlineVisitor < YARP::Visitor
    attr_reader :source, :newlines

    def initialize(source)
      @source = source
      @newlines = []
    end

    def visit(node)
      newlines << source.line(node.location.start_offset) if node&.newline?
      super(node)
    end
  end

  base = File.dirname(__dir__)
  Dir["{lib,test}/**/*.rb", base: base].each do |relative|
    define_method("test_newline_flags_#{relative}") do
      assert_newlines(base, relative)
    end
  end

  private

  def assert_newlines(base, relative)
    filepath = File.join(base, relative)
    source = File.read(filepath, binmode: true, external_encoding: Encoding::UTF_8)
    expected = rubyvm_lines(source)

    result = YARP.parse_file(filepath)
    assert_empty result.errors

    result.mark_newlines
    visitor = NewlineVisitor.new(result.source)

    result.value.accept(visitor)
    actual = visitor.newlines

    source.each_line.with_index(1) do |line, line_number|
      # Lines like `while (foo = bar)` result in two line flags in the bytecode
      # but only one newline flag in the AST. We need to remove the extra line
      # flag from the bytecode to make the test pass.
      if line.match?(/while \(/)
        index = expected.index(line_number)
        expected.delete_at(index) if index
      end

      # Lines like `foo =` where the value is on the next line result in another
      # line flag in the bytecode but only one newline flag in the AST.
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

  def ignore_warnings
    previous_verbosity = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = previous_verbosity
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
end
