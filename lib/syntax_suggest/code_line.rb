# frozen_string_literal: true

module SyntaxSuggest
  # Represents a single line of code of a given source file
  #
  # This object contains metadata about the line such as
  # amount of indentation, if it is empty or not, and
  # lexical data, such as if it has an `end` or a keyword
  # in it.
  #
  # Visibility of lines can be toggled off. Marking a line as invisible
  # indicates that it should not be used for syntax checks.
  # It's functionally the same as commenting it out.
  #
  # Example:
  #
  #   line = CodeLine.from_source("def foo\n").first
  #   line.number => 1
  #   line.empty? # => false
  #   line.visible? # => true
  #   line.mark_invisible
  #   line.visible? # => false
  #
  class CodeLine
    TRAILING_SLASH = ("\\" + $/).freeze

    # Returns an array of CodeLine objects
    # from the source string
    def self.from_source(source)
      source = +source
      parse_result = Prism.parse_lex(source)
      ast, tokens = parse_result.value

      clean_comments!(source, parse_result.comments)

      visitor = Visitor.new
      visitor.visit(ast)
      tokens.sort_by! { |token, _state| token.location.start_line }

      prev_token = nil
      tokens.map! do |token, _state|
        prev_token = Token.new(token, prev_token, visitor)
      end

      tokens_for_line = tokens.each_with_object(Hash.new { |h, k| h[k] = [] }) { |token, hash| hash[token.line] << token }
      source.lines.map.with_index do |line, index|
        CodeLine.new(
          line: line,
          index: index,
          tokens: tokens_for_line[index + 1],
          consecutive: visitor.consecutive_lines.include?(index + 1)
        )
      end
    end

    # Remove comments that apear on their own in source. They will never be the cause
    # of syntax errors and are just visual noise. Example:
    #
    #   source = +<<~RUBY
    #     # Comment-only line
    #     foo # Inline comment
    #   RUBY
    #   CodeLine.clean_comments!(source, Prism.parse(source).comments)
    #   source # => "\nfoo # Inline comment\n"
    def self.clean_comments!(source, comments)
      # Iterate backwards since we are modifying the source in place and must preserve
      # the offsets. Prism comments are sorted by their location in the source.
      comments.reverse_each do |comment|
        next if comment.trailing?
        source.bytesplice(comment.location.start_offset, comment.location.length, "")
      end
    end

    attr_reader :line, :index, :tokens, :line_number, :indent
    def initialize(line:, index:, tokens:, consecutive:)
      @tokens = tokens
      @line = line
      @index = index
      @consecutive = consecutive
      @original = line
      @line_number = @index + 1
      strip_line = line.dup
      strip_line.lstrip!

      @indent = if (@empty = strip_line.empty?)
        line.length - 1 # Newline removed from strip_line is not "whitespace"
      else
        line.length - strip_line.length
      end

      set_kw_end
    end

    # Used for stable sort via indentation level
    #
    # Ruby's sort is not "stable" meaning that when
    # multiple elements have the same value, they are
    # not guaranteed to return in the same order they
    # were put in.
    #
    # So when multiple code lines have the same indentation
    # level, they're sorted by their index value which is unique
    # and consistent.
    #
    # This is mostly needed for consistency of the test suite
    def indent_index
      @indent_index ||= [indent, index]
    end
    alias_method :number, :line_number

    # Returns true if the code line is determined
    # to contain a keyword that matches with an `end`
    #
    # For example: `def`, `do`, `begin`, `ensure`, etc.
    def is_kw?
      @is_kw
    end

    # Returns true if the code line is determined
    # to contain an `end` keyword
    def is_end?
      @is_end
    end

    # Used to hide lines
    #
    # The search alorithm will group lines into blocks
    # then if those blocks are determined to represent
    # valid code they will be hidden
    def mark_invisible
      @line = ""
    end

    # Means the line was marked as "invisible"
    # Confusingly, "empty" lines are visible...they
    # just don't contain any source code other than a newline ("\n").
    def visible?
      !line.empty?
    end

    # Opposite or `visible?` (note: different than `empty?`)
    def hidden?
      !visible?
    end

    # An `empty?` line is one that was originally left
    # empty in the source code, while a "hidden" line
    # is one that we've since marked as "invisible"
    def empty?
      @empty
    end

    # Opposite of `empty?` (note: different than `visible?`)
    def not_empty?
      !empty?
    end

    # Renders the given line
    #
    # Also allows us to represent source code as
    # an array of code lines.
    #
    # When we have an array of code line elements
    # calling `join` on the array will call `to_s`
    # on each element, which essentially converts
    # it back into it's original source string.
    def to_s
      line
    end

    # When the code line is marked invisible
    # we retain the original value of it's line
    # this is useful for debugging and for
    # showing extra context
    #
    # DisplayCodeWithLineNumbers will render
    # all lines given to it, not just visible
    # lines, it uses the original method to
    # obtain them.
    attr_reader :original

    # Comparison operator, needed for equality
    # and sorting
    def <=>(other)
      index <=> other.index
    end

    # Can this line be logically joined together
    # with the following line? Determined by walking
    # the AST
    def consecutive?
      @consecutive
    end

    # Determines if the given line has a trailing slash.
    # Simply check if the line contains a backslash after
    # the content of the last token.
    #
    #     lines = CodeLine.from_source(<<~EOM)
    #       it "foo" \
    #     EOM
    #     expect(lines.first.trailing_slash?).to eq(true)
    #
    def trailing_slash?
      return unless (last = @tokens.last)
      @line.byteindex(TRAILING_SLASH, last.location.end_column) != nil
    end

    private def set_kw_end
      kw_count = 0
      end_count = 0

      @tokens.each do |token|
        kw_count += 1 if token.is_kw?
        end_count += 1 if token.is_end?
      end

      @is_kw = (kw_count - end_count) > 0
      @is_end = (end_count - kw_count) > 0
    end
  end
end
