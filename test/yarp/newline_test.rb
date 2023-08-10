# frozen_string_literal: true

require "yarp_test_helper"

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

  root = File.dirname(__dir__)

  Dir["{lib,test}/**/*.rb", base: root].each do |relative|
    # Our newlines are not exact, so for now skip a couple of files that are
    # marked as incorrect.
    next if relative == "test/parse_serialize_test.rb"

    filepath = File.join(root, relative)

    define_method "test_newline_flags_#{relative}" do
      source = File.read(filepath, binmode: true, external_encoding: Encoding::UTF_8)
      expected = rubyvm_lines(source)

      result = YARP.parse_file(filepath)
      assert_empty result.errors

      result.mark_newlines
      visitor = NewlineVisitor.new(result.source)
      result.value.accept(visitor)
      actual = visitor.newlines

      if relative == "lib/yarp/serialize.rb"
        # while (b = io.getbyte) >= 128 has 2 newline flags
        line_number = source.lines.index { |line| line.include?('while (b = io.getbyte) >= 128') } + 1
        expected.delete_at(expected.index(line_number))
      elsif relative == "lib/yarp/lex_compat.rb"
        # extra flag for: dedent_next =\n  ((token.event: due to bytecode order
        # different line for: token =\n  case event: due to bytecode order
        # extra flag for: lex_state =\n  if RIPPER: due to bytecode order
        source.lines.each.with_index(1) do |line, line_number|
          if line =~ /^\s+\w+ =$/
            actual.delete(line_number)

            # different line for: token =\n  case event: due to bytecode order
            if line =~ /token =$/
              expected.delete(line_number + 1)
            end
          end
        end

        # extra flag for: (token[2].start_with?("\#$") || token[2].start_with?("\#@"))
        # unclear when ParenthesesNode should allow a second flag on the same line or not
        index = source.lines.index do |line|
          line.include?('(token[2].start_with?("\#$") || token[2].start_with?("\#@"))')
        end
        actual.delete(index + 1)
      elsif relative == "test/parse_test.rb"
        line_number = source.lines.index { |line| line.include?("while (node = queue.shift)") } + 1
        expected.delete_at(expected.index(line_number))
      end

      assert_equal expected, actual
    end
  end

  private

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
