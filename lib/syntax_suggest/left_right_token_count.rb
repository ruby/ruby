# frozen_string_literal: true

module SyntaxSuggest
  # Find mis-matched syntax based on lexical count
  #
  # Used for detecting missing pairs of elements
  # each keyword needs an end, each '{' needs a '}'
  # etc.
  #
  # Example:
  #
  #   left_right = LeftRightTokenCount.new
  #   left_right.count_kw
  #   left_right.missing.first
  #   # => "end"
  #
  #   left_right = LeftRightTokenCount.new
  #   source = "{ a: b, c: d" # Note missing '}'
  #   LexAll.new(source: source).each do |token|
  #     left_right.count_token(token)
  #   end
  #   left_right.missing.first
  #   # => "}"
  class LeftRightTokenCount
    def initialize
      @kw_count = 0
      @end_count = 0

      @count_for_char = {
        "{" => 0,
        "}" => 0,
        "[" => 0,
        "]" => 0,
        "(" => 0,
        ")" => 0,
        "|" => 0
      }
    end

    def count_kw
      @kw_count += 1
    end

    def count_end
      @end_count += 1
    end

    # Count source code characters
    #
    # Example:
    #
    #   token = CodeLine.from_source("{").first.tokens.first
    #   left_right = LeftRightTokenCount.new
    #   left_right.count_token(Token.new(token)
    #   left_right.count_for_char("{")
    #   # => 1
    #   left_right.count_for_char("}")
    #   # => 0
    def count_token(token)
      case token.type
      when :STRING_CONTENT
        # ^^^
        # Means it's a string or a symbol `"{"` rather than being
        # part of a data structure (like a hash) `{ a: b }`
        # ignore it.
      when :PERCENT_UPPER_W, :PERCENT_UPPER_I, :PERCENT_LOWER_W,
           :PERCENT_LOWER_I, :REGEXP_BEGIN, :STRING_BEGIN
        # ^^^
        # Handle shorthand syntaxes like `%Q{ i am a string }`
        #
        # The start token will be the full thing `%Q{` but we
        # need to count it as if it's a `{`. Any token
        # can be used
        char = token.value[-1]
        @count_for_char[char] += 1 if @count_for_char.key?(char)
      when :EMBEXPR_BEGIN
        # ^^^
        # Embedded string expressions like `"#{foo} <-embed"`
        # are parsed with chars:
        #
        # `#{` as :EMBEXPR_BEGIN
        #  `}` as :EMBEXPR_END
        #
        # When we see `#{` count it as a `{` or we will
        # have a mis-match count.
        #
        @count_for_char["{"] += 1
      else
        @end_count += 1 if token.is_end?
        @kw_count += 1 if token.is_kw?
        @count_for_char[token.value] += 1 if @count_for_char.key?(token.value)
      end
    end

    def count_for_char(char)
      @count_for_char[char]
    end

    # Returns an array of missing syntax characters
    # or `"end"` or `"keyword"`
    #
    #   left_right.missing
    #   # => ["}"]
    def missing
      out = missing_pairs
      out << missing_pipe
      out << missing_keyword_end
      out.compact!
      out
    end

    PAIRS = {
      "{" => "}",
      "[" => "]",
      "(" => ")"
    }.freeze

    # Opening characters like `{` need closing characters # like `}`.
    #
    # When a mis-match count is detected, suggest the
    # missing member.
    #
    # For example if there are 3 `}` and only two `{`
    # return `"{"`
    private def missing_pairs
      PAIRS.map do |(left, right)|
        case @count_for_char[left] <=> @count_for_char[right]
        when 1
          right
        when 0
          nil
        when -1
          left
        end
      end
    end

    # Keywords need ends and ends need keywords
    #
    # If we have more keywords, there's a missing `end`
    # if we have more `end`-s, there's a missing keyword
    private def missing_keyword_end
      case @kw_count <=> @end_count
      when 1
        "end"
      when 0
        nil
      when -1
        "keyword"
      end
    end

    # Pipes come in pairs.
    # If there's an odd number of pipes then we
    # are missing one
    private def missing_pipe
      if @count_for_char["|"].odd?
        "|"
      end
    end
  end
end
