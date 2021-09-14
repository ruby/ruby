# frozen_string_literal: true

module DeadEnd
  # Takes in a source, and returns blocks containing each heredoc
  class HeredocBlockParse
    private; attr_reader :code_lines, :lex; public

    def initialize(source:, code_lines: )
      @code_lines = code_lines
      @lex = LexAll.new(source: source)
    end

    def call
      blocks = []
      beginning = []
      @lex.each do |lex|
        case lex.type
        when :on_heredoc_beg
          beginning << lex.line
        when :on_heredoc_end
          start_index = beginning.pop - 1
          end_index = lex.line - 1
          blocks << CodeBlock.new(lines: code_lines[start_index..end_index])
        end
      end

      blocks
    end
  end
end
