# frozen_string_literal: true

module DeadEnd
  # The main function of the frontier is to hold the edges of our search and to
  # evaluate when we can stop searching.
  #
  # ## Knowing where we've been
  #
  # Once a code block is generated it is added onto the frontier where it will be
  # sorted and then the frontier can be filtered. Large blocks that totally contain a
  # smaller block will cause the smaller block to be evicted.
  #
  #   CodeFrontier#<<(block) # Adds block to frontier
  #   CodeFrontier#pop # Removes block from frontier
  #
  # ## Knowing where we can go
  #
  # Internally it keeps track of "unvisited" lines which is exposed via `next_indent_line`
  # when called this will return a line of code with the most indentation.
  #
  # This line of code can be used to build a CodeBlock and then when that code block
  # is added back to the frontier, then the lines are removed from the
  # "unvisited" so we don't double-create the same block.
  #
  #   CodeFrontier#next_indent_line # Shows next line
  #   CodeFrontier#register_indent_block(block) # Removes lines from unvisited
  #
  # ## Knowing when to stop
  #
  # The frontier holds the syntax error when removing all code blocks from the original
  # source document allows it to be parsed as syntatically valid:
  #
  #   CodeFrontier#holds_all_syntax_errors?
  #
  # ## Filtering false positives
  #
  # Once the search is completed, the frontier will have many blocks that do not contain
  # the syntax error. To filter to the smallest subset that does call:
  #
  #   CodeFrontier#detect_invalid_blocks
  class CodeFrontier
    def initialize(code_lines: )
      @code_lines = code_lines
      @frontier = []
      @unvisited_lines = @code_lines.sort_by(&:indent_index)
    end

    def count
      @frontier.count
    end

    # Returns true if the document is valid with all lines
    # removed. By default it checks all blocks in present in
    # the frontier array, but can be used for arbitrary arrays
    # of codeblocks as well
    def holds_all_syntax_errors?(block_array = @frontier)
      without_lines = block_array.map do |block|
        block.lines
      end

      DeadEnd.valid_without?(
        without_lines: without_lines,
        code_lines: @code_lines
      )
    end

    # Returns a code block with the largest indentation possible
    def pop
      return @frontier.pop
    end

    def next_indent_line
      @unvisited_lines.last
    end

    def expand?
      return false if @frontier.empty?
      return true if @unvisited_lines.empty?

      frontier_indent = @frontier.last.current_indent
      unvisited_indent= next_indent_line.indent

      if ENV["DEBUG"]
        puts "```"
        puts @frontier.last.to_s
        puts "```"
        puts "  @frontier indent: #{frontier_indent}"
        puts "  @unvisited indent:     #{unvisited_indent}"
      end

      # Expand all blocks before moving to unvisited lines
      frontier_indent >= unvisited_indent
    end

    def register_indent_block(block)
      @unvisited_lines -= block.lines
      self
    end

    # Add a block to the frontier
    #
    # This method ensures the frontier always remains sorted (in indentation order)
    # and that each code block's lines are removed from the indentation hash so we
    # don't re-evaluate the same line multiple times.
    def <<(block)
      register_indent_block(block)

      # Make sure we don't double expand, if a code block fully engulfs another code block, keep the bigger one
      @frontier.reject! {|b|
        b.starts_at >= block.starts_at && b.ends_at <= block.ends_at
      }
      @frontier << block
      @frontier.sort!

      self
    end

    # Example:
    #
    #   combination([:a, :b, :c, :d])
    #   # => [[:a], [:b], [:c], [:d], [:a, :b], [:a, :c], [:a, :d], [:b, :c], [:b, :d], [:c, :d], [:a, :b, :c], [:a, :b, :d], [:a, :c, :d], [:b, :c, :d], [:a, :b, :c, :d]]
    def self.combination(array)
      guesses = []
      1.upto(array.length).each do |size|
        guesses.concat(array.combination(size).to_a)
      end
      guesses
    end

    # Given that we know our syntax error exists somewhere in our frontier, we want to find
    # the smallest possible set of blocks that contain all the syntax errors
    def detect_invalid_blocks
      self.class.combination(@frontier.select(&:invalid?)).detect do |block_array|
        holds_all_syntax_errors?(block_array)
      end || []
    end
  end
end
