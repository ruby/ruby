# frozen_string_literal: true

module SyntaxSuggest
  # This class is responsible for taking a code block that exists
  # at a far indentaion and then iteratively increasing the block
  # so that it captures everything within the same indentation block.
  #
  #   def dog
  #     puts "bow"
  #     puts "wow"
  #   end
  #
  # block = BlockExpand.new(code_lines: code_lines)
  #   .call(CodeBlock.new(lines: code_lines[1]))
  #
  # puts block.to_s
  # # => puts "bow"
  #      puts "wow"
  #
  #
  # Once a code block has captured everything at a given indentation level
  # then it will expand to capture surrounding indentation.
  #
  # block = BlockExpand.new(code_lines: code_lines)
  #   .call(block)
  #
  # block.to_s
  # # => def dog
  #        puts "bow"
  #        puts "wow"
  #      end
  #
  class BlockExpand
    def initialize(code_lines:)
      @code_lines = code_lines
    end

    def call(block)
      if (next_block = expand_neighbors(block))
        return next_block
      end

      expand_indent(block)
    end

    def expand_indent(block)
      AroundBlockScan.new(code_lines: @code_lines, block: block)
        .skip(:hidden?)
        .stop_after_kw
        .scan_adjacent_indent
        .code_block
    end

    def expand_neighbors(block)
      expanded_lines = AroundBlockScan.new(code_lines: @code_lines, block: block)
        .skip(:hidden?)
        .stop_after_kw
        .scan_neighbors
        .scan_while { |line| line.empty? } # Slurp up empties
        .lines

      if block.lines == expanded_lines
        nil
      else
        CodeBlock.new(lines: expanded_lines)
      end
    end

    # Managable rspec errors
    def inspect
      "#<SyntaxSuggest::CodeBlock:0x0000123843lol >"
    end
  end
end
