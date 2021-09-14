# frozen_string_literal: true
module DeadEnd
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
    def initialize(code_lines: )
      @code_lines = code_lines
    end

    def call(block)
      if (next_block = expand_neighbors(block, grab_empty: true))
        return next_block
      end

      expand_indent(block)
    end

    def expand_indent(block)
      block = AroundBlockScan.new(code_lines: @code_lines, block: block)
        .skip(:hidden?)
        .stop_after_kw
        .scan_adjacent_indent
        .code_block
    end

    def expand_neighbors(block, grab_empty: true)
      scan = AroundBlockScan.new(code_lines: @code_lines, block: block)
        .skip(:hidden?)
        .stop_after_kw
        .scan_neighbors

      # Slurp up empties
      if grab_empty
        scan = AroundBlockScan.new(code_lines: @code_lines, block: scan.code_block)
          .scan_while {|line| line.empty? || line.hidden? }
      end

      new_block = scan.code_block

      if block.lines == new_block.lines
        return nil
      else
        return new_block
      end
    end
  end
end
