# frozen_string_literal: true

require_relative "scan_history"

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
  class AroundBlockScan
    def initialize(code_lines:, block:)
      @code_lines = code_lines
      @orig_indent = block.current_indent

      @stop_after_kw = false
      @force_add_empty = false
      @force_add_hidden = false
      @target_indent = nil

      @scanner = ScanHistory.new(code_lines: code_lines, block: block)
    end

    # When using this flag, `scan_while` will
    # bypass the block it's given and always add a
    # line that responds truthy to `CodeLine#hidden?`
    #
    # Lines are hidden when they've been evaluated by
    # the parser as part of a block and found to contain
    # valid code.
    def force_add_hidden
      @force_add_hidden = true
      self
    end

    # When using this flag, `scan_while` will
    # bypass the block it's given and always add a
    # line that responds truthy to `CodeLine#empty?`
    #
    # Empty lines contain no code, only whitespace such
    # as leading spaces a newline.
    def force_add_empty
      @force_add_empty = true
      self
    end

    # Tells `scan_while` to look for mismatched keyword/end-s
    #
    # When scanning up, if we see more keywords then end-s it will
    # stop. This might happen when scanning outside of a method body.
    # the first scan line up would be a keyword and this setting would
    # trigger a stop.
    #
    # When scanning down, stop if there are more end-s than keywords.
    def stop_after_kw
      @stop_after_kw = true
      self
    end

    # Main work method
    #
    # The scan_while method takes a block that yields lines above and
    # below the block. If the yield returns true, the @before_index
    # or @after_index are modified to include the matched line.
    #
    # In addition to yielding individual lines, the internals of this
    # object give a mini DSL to handle common situations such as
    # stopping if we've found a keyword/end mis-match in one direction
    # or the other.
    def scan_while
      stop_next_up = false
      stop_next_down = false

      @scanner.scan(
        up: ->(line, kw_count, end_count) {
          next false if stop_next_up
          next true if @force_add_hidden && line.hidden?
          next true if @force_add_empty && line.empty?

          if @stop_after_kw && kw_count > end_count
            stop_next_up = true
          end

          yield line
        },
        down: ->(line, kw_count, end_count) {
          next false if stop_next_down
          next true if @force_add_hidden && line.hidden?
          next true if @force_add_empty && line.empty?

          if @stop_after_kw && end_count > kw_count
            stop_next_down = true
          end

          yield line
        }
      )

      self
    end

    # Shows surrounding kw/end pairs
    #
    # The purpose of showing these extra pairs is due to cases
    # of ambiguity when only one visible line is matched.
    #
    # For example:
    #
    #     1  class Dog
    #     2    def bark
    #     4    def eat
    #     5    end
    #     6  end
    #
    # In this case either line 2 could be missing an `end` or
    # line 4 was an extra line added by mistake (it happens).
    #
    # When we detect the above problem it shows the issue
    # as only being on line 2
    #
    #     2    def bark
    #
    # Showing "neighbor" keyword pairs gives extra context:
    #
    #     2    def bark
    #     4    def eat
    #     5    end
    #
    def capture_before_after_kws
      lines = []
      up_stop_next = false
      down_stop_next = false
      @scanner.commit_if_changed

      lines = []
      @scanner.scan(
        up: ->(line, kw_count, end_count) {
          break if up_stop_next
          next true if line.empty?
          break if line.indent < @orig_indent
          next true if line.indent != @orig_indent

          # If we're going up and have one complete kw/end pair, stop
          if kw_count != 0 && kw_count == end_count
            lines << line
            break
          end

          lines << line if line.is_kw? || line.is_end?
        },
        down: ->(line, kw_count, end_count) {
          break if down_stop_next
          next true if line.empty?
          break if line.indent < @orig_indent
          next true if line.indent != @orig_indent

          # if we're going down and have one complete kw/end pair,stop
          if kw_count != 0 && kw_count == end_count
            lines << line
            break
          end

          lines << line if line.is_kw? || line.is_end?
        }
      )
      @scanner.try_rollback
      lines
    end

    # Shows the context around code provided by "falling" indentation
    #
    #
    # If this is the original code lines:
    #
    #   class OH
    #     def hello
    #       it "foo" do
    #     end
    #   end
    #
    # And this is the line that is captured
    #
    #       it "foo" do
    #
    # It will yield its surrounding context:
    #
    #   class OH
    #     def hello
    #     end
    #   end
    #
    # Example:
    #
    #   AroundBlockScan.new(
    #       block: block,
    #       code_lines: @code_lines
    #   ).on_falling_indent do |line|
    #     @lines_to_output << line
    #   end
    #
    def on_falling_indent
      last_indent_up = @orig_indent
      last_indent_down = @orig_indent

      @scanner.commit_if_changed
      @scanner.scan(
        up: ->(line, _, _) {
          next true if line.empty?

          if line.indent < last_indent_up
            yield line
            last_indent_up = line.indent
          end
          true
        },
        down: ->(line, _, _) {
          next true if line.empty?
          if line.indent < last_indent_down
            yield line
            last_indent_down = line.indent
          end
          true
        }
      )
      @scanner.try_rollback
      self
    end

    # Scanning is intentionally conservative because
    # we have no way of rolling back an agressive block (at this time)
    #
    # If a block was stopped for some trivial reason, (like an empty line)
    # but the next line would have caused it to be balanced then we
    # can check that condition and grab just one more line either up or
    # down.
    #
    # For example, below if we're scanning up, line 2 might cause
    # the scanning to stop. This is because empty lines might
    # denote logical breaks where the user intended to chunk code
    # which is a good place to stop and check validity. Unfortunately
    # it also means we might have a "dangling" keyword or end.
    #
    #   1 def bark
    #   2
    #   3 end
    #
    # If lines 2 and 3 are in the block, then when this method is
    # run it would see it is unbalanced, but that acquiring line 1
    # would make it balanced, so that's what it does.
    def lookahead_balance_one_line
      kw_count = 0
      end_count = 0
      lines.each do |line|
        kw_count += 1 if line.is_kw?
        end_count += 1 if line.is_end?
      end

      return self if kw_count == end_count # nothing to balance

      # More ends than keywords, check if we can balance expanding up
      next_up = @scanner.next_up
      next_down = @scanner.next_down
      if (end_count - kw_count) == 1 && next_up
        if next_up.is_kw? && next_up.indent >= @orig_indent
          @scanner.scan(
            up: ->(line, _, _) { line == next_up },
            down: ->(line, _, _) { false }
          )
        end

      # More keywords than ends, check if we can balance by expanding down
      elsif (kw_count - end_count) == 1 && next_down
        if next_down.is_end? && next_down.indent >= @orig_indent
          @scanner.scan(
            up: ->(line, _, _) { false },
            down: ->(line) { line == next_down }
          )
        end
      end
      self
    end

    # Finds code lines at the same or greater indentation and adds them
    # to the block
    def scan_neighbors_not_empty
      @target_indent = @orig_indent
      scan_while { |line| line.not_empty? && line.indent >= @target_indent }
    end

    # Scan blocks based on indentation of next line above/below block
    #
    # Determines indentaion of the next line above/below the current block.
    #
    # Normally this is called when a block has expanded to capture all "neighbors"
    # at the same (or greater) indentation and needs to expand out. For example
    # the `def/end` lines surrounding a method.
    def scan_adjacent_indent
      before_after_indent = []

      before_after_indent << (@scanner.next_up&.indent || 0)
      before_after_indent << (@scanner.next_down&.indent || 0)

      @target_indent = before_after_indent.min
      scan_while { |line| line.not_empty? && line.indent >= @target_indent }

      self
    end

    # Return the currently matched lines as a `CodeBlock`
    #
    # When a `CodeBlock` is created it will gather metadata about
    # itself, so this is not a free conversion. Avoid allocating
    # more CodeBlock's than needed
    def code_block
      CodeBlock.new(lines: lines)
    end

    # Returns the lines matched by the current scan as an
    # array of CodeLines
    def lines
      @scanner.lines
    end

    # Managable rspec errors
    def inspect
      "#<#{self.class}:0x0000123843lol >"
    end
  end
end
