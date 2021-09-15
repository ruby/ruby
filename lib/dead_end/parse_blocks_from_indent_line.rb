# frozen_string_literal: true

module DeadEnd
  # This class is responsible for generating initial code blocks
  # that will then later be expanded.
  #
  # The biggest concern when guessing about code blocks, is accidentally
  # grabbing one that contains only an "end". In this example:
  #
  #   def dog
  #     begonn # mispelled `begin`
  #     puts "bark"
  #     end
  #   end
  #
  # The following lines would be matched (from bottom to top):
  #
  #   1) end
  #
  #   2) puts "bark"
  #      end
  #
  #   3) begonn
  #      puts "bark"
  #      end
  #
  # At this point it has no where else to expand, and it will yield this inner
  # code as a block
  class ParseBlocksFromIndentLine
    attr_reader :code_lines

    def initialize(code_lines: )
      @code_lines = code_lines
    end

    # Builds blocks from bottom up
    def each_neighbor_block(target_line)
      scan = AroundBlockScan.new(code_lines: code_lines, block: CodeBlock.new(lines: target_line))
        .skip(:empty?)
        .skip(:hidden?)
        .scan_while {|line| line.indent >= target_line.indent }

      neighbors = scan.code_block.lines

      until neighbors.empty?
        lines = [neighbors.pop]
        while (block = CodeBlock.new(lines: lines)) && block.invalid? && neighbors.any?
          lines.prepend neighbors.pop
        end

        yield block if block
      end
    end
  end
end

