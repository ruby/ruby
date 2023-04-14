# frozen_string_literal: true

module SyntaxSuggest
  # Scans up/down from the given block
  #
  # You can snapshot a change by committing it and rolling back.
  #
  class ScanHistory
    attr_reader :before_index, :after_index

    def initialize(code_lines:, block:)
      @code_lines = code_lines
      @history = [block]
      refresh_index
    end

    def commit_if_changed
      if changed?
        @history << CodeBlock.new(lines: @code_lines[before_index..after_index])
        refresh_index
      end

      self
    end

    def try_rollback
      if @history.length > 1
        @history.pop
        refresh_index
      end

      self
    end

    def changed?
      @before_index != current.lines.first.index ||
        @after_index != current.lines.last.index
    end

    # Iterates up and down
    #
    # Returns line, kw_count, end_count for each iteration
    def scan(up:, down:)
      kw_count = 0
      end_count = 0

      up_index = before_lines.reverse_each.take_while do |line|
        kw_count += 1 if line.is_kw?
        end_count += 1 if line.is_end?
        up.call(line, kw_count, end_count)
      end.last&.index

      kw_count = 0
      end_count = 0

      down_index = after_lines.each.take_while do |line|
        kw_count += 1 if line.is_kw?
        end_count += 1 if line.is_end?
        down.call(line, kw_count, end_count)
      end.last&.index

      @before_index = if up_index && up_index < @before_index
        up_index
      else
        @before_index
      end

      @after_index = if down_index && down_index > @after_index
        down_index
      else
        @after_index
      end

      self
    end

    def next_up
      return nil if @before_index <= 0

      @code_lines[@before_index - 1]
    end

    def next_down
      return nil if @after_index >= @code_lines.length

      @code_lines[@after_index + 1]
    end

    def lines
      @code_lines[@before_index..@after_index]
    end

    private def before_lines
      @code_lines[0...@before_index] || []
    end

    # Returns an array of all the CodeLines that exist after
    # the currently scanned block
    private def after_lines
      @code_lines[@after_index.next..-1] || []
    end

    private def current
      @history.last
    end

    private def refresh_index
      @before_index = current.lines.first.index
      @after_index = current.lines.last.index
      self
    end
  end
end
