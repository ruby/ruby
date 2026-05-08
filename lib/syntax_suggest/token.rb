# frozen_string_literal: true

module SyntaxSuggest
  # Value object for accessing lex values
  #
  # This lex:
  #
  #   [IDENTIFIER(1,0)-(1,8)("describe"), 32]
  #
  # Would translate into:
  #
  #  lex.location # => (1,0)-(1,8)
  #  lex.type # => :IDENTIFIER
  #  lex.token # => "describe"
  class Token
    attr_reader :location, :type, :value

    KW_TYPES = %i[
      KEYWORD_IF KEYWORD_UNLESS KEYWORD_WHILE KEYWORD_UNTIL
      KEYWORD_DEF KEYWORD_CASE KEYWORD_FOR KEYWORD_BEGIN KEYWORD_CLASS KEYWORD_MODULE KEYWORD_DO KEYWORD_DO_LOOP
    ].to_set.freeze
    private_constant :KW_TYPES

    def initialize(prism_token, previous_prism_token, visitor)
      @location = prism_token.location
      @type = prism_token.type
      @value = prism_token.value

      # Prism lexes `:module` as SYMBOL_BEGIN, KEYWORD_MODULE
      # https://github.com/ruby/prism/issues/3940
      symbol_content = previous_prism_token&.type == :SYMBOL_BEGIN
      @is_kw = KW_TYPES.include?(@type)
      @is_kw = false if symbol_content || visitor.endless_def_keyword_offsets.include?(@location.start_offset)
      @is_end = @type == :KEYWORD_END
    end

    def line
      @location.start_line
    end

    def is_end?
      @is_end
    end

    def is_kw?
      @is_kw
    end
  end
end
