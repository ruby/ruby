# frozen_string_literal: true

module SyntaxSuggest
  # This class is useful for exploring contents before and after
  # a block
  #
  # It searches above and below the passed in block to match for
  # whatever criteria you give it:
  #
  # Example:
  #
  #   def dog         # 1
  #     puts "bark"   # 2
  #     puts "bark"   # 3
  #   end             # 4
  #
  #   scan = AroundBlockScan.new(
  #     code_lines: code_lines
  #     block: CodeBlock.new(lines: code_lines[1])
  #   )
  #
  #   scan.scan_while { true }
  #
  #   puts scan.before_index # => 0
  #   puts scan.after_index  # => 3
  #
  # Contents can also be filtered using AroundBlockScan#skip
  #
  # To grab the next surrounding indentation use AroundBlockScan#scan_adjacent_indent
  class AroundBlockScan
    def initialize(code_lines:, block:)
      @code_lines = code_lines
      @orig_before_index = block.lines.first.index
      @orig_after_index = block.lines.last.index
      @orig_indent = block.current_indent
      @skip_array = []
      @after_array = []
      @before_array = []
      @stop_after_kw = false

      @skip_hidden = false
      @skip_empty = false
    end

    def skip(name)
      case name
      when :hidden?
        @skip_hidden = true
      when :empty?
        @skip_empty = true
      else
        raise "Unsupported skip #{name}"
      end
      self
    end

    def stop_after_kw
      @stop_after_kw = true
      self
    end

    def scan_while
      stop_next = false

      kw_count = 0
      end_count = 0
      index = before_lines.reverse_each.take_while do |line|
        next false if stop_next
        next true if @skip_hidden && line.hidden?
        next true if @skip_empty && line.empty?

        kw_count += 1 if line.is_kw?
        end_count += 1 if line.is_end?
        if @stop_after_kw && kw_count > end_count
          stop_next = true
        end

        yield line
      end.last&.index

      if index && index < before_index
        @before_index = index
      end

      stop_next = false
      kw_count = 0
      end_count = 0
      index = after_lines.take_while do |line|
        next false if stop_next
        next true if @skip_hidden && line.hidden?
        next true if @skip_empty && line.empty?

        kw_count += 1 if line.is_kw?
        end_count += 1 if line.is_end?
        if @stop_after_kw && end_count > kw_count
          stop_next = true
        end

        yield line
      end.last&.index

      if index && index > after_index
        @after_index = index
      end
      self
    end

    def capture_neighbor_context
      lines = []
      kw_count = 0
      end_count = 0
      before_lines.reverse_each do |line|
        next if line.empty?
        break if line.indent < @orig_indent
        next if line.indent != @orig_indent

        kw_count += 1 if line.is_kw?
        end_count += 1 if line.is_end?
        if kw_count != 0 && kw_count == end_count
          lines << line
          break
        end

        lines << line
      end

      lines.reverse!

      kw_count = 0
      end_count = 0
      after_lines.each do |line|
        next if line.empty?
        break if line.indent < @orig_indent
        next if line.indent != @orig_indent

        kw_count += 1 if line.is_kw?
        end_count += 1 if line.is_end?
        if kw_count != 0 && kw_count == end_count
          lines << line
          break
        end

        lines << line
      end

      lines
    end

    def on_falling_indent
      last_indent = @orig_indent
      before_lines.reverse_each do |line|
        next if line.empty?
        if line.indent < last_indent
          yield line
          last_indent = line.indent
        end
      end

      last_indent = @orig_indent
      after_lines.each do |line|
        next if line.empty?
        if line.indent < last_indent
          yield line
          last_indent = line.indent
        end
      end
    end

    def scan_neighbors
      scan_while { |line| line.not_empty? && line.indent >= @orig_indent }
    end

    def next_up
      @code_lines[before_index.pred]
    end

    def next_down
      @code_lines[after_index.next]
    end

    def scan_adjacent_indent
      before_after_indent = []
      before_after_indent << (next_up&.indent || 0)
      before_after_indent << (next_down&.indent || 0)

      indent = before_after_indent.min
      scan_while { |line| line.not_empty? && line.indent >= indent }

      self
    end

    def start_at_next_line
      before_index
      after_index
      @before_index -= 1
      @after_index += 1
      self
    end

    def code_block
      CodeBlock.new(lines: lines)
    end

    def lines
      @code_lines[before_index..after_index]
    end

    def before_index
      @before_index ||= @orig_before_index
    end

    def after_index
      @after_index ||= @orig_after_index
    end

    private def before_lines
      @code_lines[0...before_index] || []
    end

    private def after_lines
      @code_lines[after_index.next..-1] || []
    end
  end
end
