# frozen_string_literal: true

module DeadEnd

  # Given a block, this method will capture surrounding
  # code to give the user more context for the location of
  # the problem.
  #
  # Return is an array of CodeLines to be rendered.
  #
  # Surrounding code is captured regardless of visible state
  #
  #   puts block.to_s # => "def bark"
  #
  #   context = CaptureCodeContext.new(
  #     blocks: block,
  #     code_lines: code_lines
  #   )
  #
  #   puts context.call.join
  #   # =>
  #     class Dog
  #       def bark
  #     end
  #
  class CaptureCodeContext
    attr_reader :code_lines

    def initialize(blocks: , code_lines:)
      @blocks = Array(blocks)
      @code_lines = code_lines
      @visible_lines = @blocks.map(&:visible_lines).flatten
      @lines_to_output = @visible_lines.dup
    end

    def call
      @blocks.each do |block|
        capture_last_end_same_indent(block)
        capture_before_after_kws(block)
        capture_falling_indent(block)
      end

      @lines_to_output.select!(&:not_empty?)
      @lines_to_output.select!(&:not_comment?)
      @lines_to_output.uniq!
      @lines_to_output.sort!

      return @lines_to_output
    end

    def capture_falling_indent(block)
      AroundBlockScan.new(
        block: block,
        code_lines: @code_lines,
      ).on_falling_indent do |line|
        @lines_to_output << line
      end
    end

    def capture_before_after_kws(block)
      around_lines = AroundBlockScan.new(code_lines: @code_lines, block: block)
        .start_at_next_line
        .capture_neighbor_context

      around_lines -= block.lines

      @lines_to_output.concat(around_lines)
    end

    # Problems heredocs are back in play
    def capture_last_end_same_indent(block)
      start_index = block.visible_lines.first.index
      lines = @code_lines[start_index..block.lines.last.index]
      kw_end_lines = lines.select {|line| line.indent == block.current_indent && (line.is_end? || line.is_kw?) }


      # TODO handle case of heredocs showing up here
      #
      # Due to https://github.com/zombocom/dead_end/issues/32
      # There's a special case where a keyword right before the last
      # end of a valid block accidentally ends up identifying that the problem
      # was with the block instead of before it. To handle that
      # special case, we can re-parse back through the internals of blocks
      # and if they have mis-matched keywords and ends show the last one
      end_lines = kw_end_lines.select(&:is_end?)
      end_lines.each_with_index  do |end_line, i|
        start_index = i.zero? ? 0 : end_lines[i-1].index
        end_index = end_line.index - 1
        lines = @code_lines[start_index..end_index]

        stop_next = false
        kw_count = 0
        end_count = 0
        lines = lines.reverse.take_while do |line|
          next false if stop_next

          end_count += 1 if line.is_end?
          kw_count += 1 if line.is_kw?

          stop_next = true if !kw_count.zero? && kw_count >= end_count
          true
        end.reverse

        next unless kw_count > end_count

        lines = lines.select {|line| line.is_kw? || line.is_end? }

        next if lines.empty?

        @lines_to_output << end_line
        @lines_to_output << lines.first
        @lines_to_output << lines.last
      end
    end
  end
end
