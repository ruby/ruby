# frozen_string_literal: true

module DeadEnd
  # Searches code for a syntax error
  #
  # The bulk of the heavy lifting is done in:
  #
  #  - CodeFrontier (Holds information for generating blocks and determining if we can stop searching)
  #  - ParseBlocksFromLine (Creates blocks into the frontier)
  #  - BlockExpand (Expands existing blocks to search more code
  #
  # ## Syntax error detection
  #
  # When the frontier holds the syntax error, we can stop searching
  #
  #   search = CodeSearch.new(<<~EOM)
  #     def dog
  #       def lol
  #     end
  #   EOM
  #
  #   search.call
  #
  #   search.invalid_blocks.map(&:to_s) # =>
  #   # => ["def lol\n"]
  #
  class CodeSearch
    private; attr_reader :frontier; public
    public; attr_reader :invalid_blocks, :record_dir, :code_lines

    def initialize(source, record_dir: ENV["DEAD_END_RECORD_DIR"] || ENV["DEBUG"] ? "tmp" : nil)
      @source = source
      if record_dir
        @time = Time.now.strftime('%Y-%m-%d-%H-%M-%s-%N')
        @record_dir = Pathname(record_dir).join(@time).tap {|p| p.mkpath }
        @write_count = 0
      end
      code_lines = source.lines.map.with_index do |line, i|
        CodeLine.new(line: line, index: i)
      end

      @code_lines = TrailingSlashJoin.new(code_lines: code_lines).call

      @frontier = CodeFrontier.new(code_lines: @code_lines)
      @invalid_blocks = []
      @name_tick = Hash.new {|hash, k| hash[k] = 0 }
      @tick = 0
      @block_expand = BlockExpand.new(code_lines: code_lines)
      @parse_blocks_from_indent_line = ParseBlocksFromIndentLine.new(code_lines: @code_lines)
    end

    # Used for debugging
    def record(block:, name: "record")
      return if !@record_dir
      @name_tick[name] += 1
      filename = "#{@write_count += 1}-#{name}-#{@name_tick[name]}.txt"
      if ENV["DEBUG"]
        puts "\n\n==== #{filename} ===="
        puts "\n```#{block.starts_at}:#{block.ends_at}"
        puts "#{block.to_s}"
        puts "```"
        puts "  block indent:     #{block.current_indent}"
      end
      @record_dir.join(filename).open(mode: "a") do |f|
        display = DisplayInvalidBlocks.new(
          blocks: block,
          terminal: false,
          code_lines: @code_lines,
        )
        f.write(display.indent display.code_with_lines)
      end
    end

    def push(block, name: )
      record(block: block, name: name)

      if block.valid?
        block.mark_invisible
        frontier << block
      else
        frontier << block
      end
    end

    # Removes the block without putting it back in the frontier
    def sweep(block:, name: )
      record(block: block, name: name)

      block.lines.each(&:mark_invisible)
      frontier.register_indent_block(block)
    end

    # Parses the most indented lines into blocks that are marked
    # and added to the frontier
    def visit_new_blocks
      max_indent = frontier.next_indent_line&.indent

      while (line = frontier.next_indent_line) && (line.indent == max_indent)

        @parse_blocks_from_indent_line.each_neighbor_block(frontier.next_indent_line) do |block|
          record(block: block, name: "add")

          block.mark_invisible if block.valid?
          push(block, name: "add")
        end
      end
    end

    # Given an already existing block in the frontier, expand it to see
    # if it contains our invalid syntax
    def expand_invalid_block
      block = frontier.pop
      return unless block

      record(block: block, name: "pop")

      # block = block.expand_until_next_boundry
      block = @block_expand.call(block)
      push(block, name: "expand")
    end

    def sweep_heredocs
      HeredocBlockParse.new(
        source: @source,
        code_lines: @code_lines
      ).call.each do |block|
        push(block, name: "heredoc")
      end
    end

    def sweep_comments
      lines = @code_lines.select(&:is_comment?)
      return if lines.empty?
      block = CodeBlock.new(lines: lines)
      sweep(block: block, name: "comments")
    end

    # Main search loop
    def call
      sweep_heredocs
      sweep_comments
      until frontier.holds_all_syntax_errors?
        @tick += 1

        if frontier.expand?
          expand_invalid_block
        else
          visit_new_blocks
        end
      end

      @invalid_blocks.concat(frontier.detect_invalid_blocks )
      @invalid_blocks.sort_by! {|block| block.starts_at }
      self
    end
  end
end
