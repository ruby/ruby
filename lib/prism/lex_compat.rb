# frozen_string_literal: true
# :markup: markdown
#--
# rbs_inline: enabled

module Prism
  # @rbs!
  #    module Translation
  #      class Ripper
  #        EXPR_NONE: Integer
  #        EXPR_BEG: Integer
  #        EXPR_MID: Integer
  #        EXPR_END: Integer
  #        EXPR_CLASS: Integer
  #        EXPR_VALUE: Integer
  #        EXPR_ARG: Integer
  #        EXPR_CMDARG: Integer
  #        EXPR_ENDARG: Integer
  #        EXPR_ENDFN: Integer
  #
  #        class Lexer < Ripper
  #          class State
  #            def self.[]: (Integer value) -> State
  #          end
  #        end
  #      end
  #    end

  # This class is responsible for lexing the source using prism and then
  # converting those tokens to be compatible with Ripper. In the vast majority
  # of cases, this is a one-to-one mapping of the token type. Everything else
  # generally lines up. However, there are a few cases that require special
  # handling.
  class LexCompat # :nodoc:
    # @rbs!
    #    # A token produced by the Ripper lexer that Prism is replicating.
    #    type lex_compat_token = [[Integer, Integer], Symbol, String, untyped]

    # A result class specialized for holding tokens produced by the lexer.
    class Result < Prism::Result
      # The list of tokens that were produced by the lexer.
      attr_reader :value #: Array[lex_compat_token]

      # Create a new lex compat result object with the given values.
      #--
      #: (Array[lex_compat_token] value, Array[Comment] comments, Array[MagicComment] magic_comments, Location? data_loc, Array[ParseError] errors, Array[ParseWarning] warnings, Source source) -> void
      def initialize(value, comments, magic_comments, data_loc, errors, warnings, source)
        @value = value
        super(comments, magic_comments, data_loc, errors, warnings, source)
      end

      # Implement the hash pattern matching interface for Result.
      #--
      #: (Array[Symbol]? keys) -> Hash[Symbol, untyped]
      def deconstruct_keys(keys) # :nodoc:
        super.merge!(value: value)
      end
    end

    # This is a mapping of prism token types to Ripper token types. This is a
    # many-to-one mapping because we split up our token types, whereas Ripper
    # tends to group them.
    RIPPER = {
      AMPERSAND: :on_op,
      AMPERSAND_AMPERSAND: :on_op,
      AMPERSAND_AMPERSAND_EQUAL: :on_op,
      AMPERSAND_DOT: :on_op,
      AMPERSAND_EQUAL: :on_op,
      BACK_REFERENCE: :on_backref,
      BACKTICK: :on_backtick,
      BANG: :on_op,
      BANG_EQUAL: :on_op,
      BANG_TILDE: :on_op,
      BRACE_LEFT: :on_lbrace,
      BRACE_RIGHT: :on_rbrace,
      BRACKET_LEFT: :on_lbracket,
      BRACKET_LEFT_ARRAY: :on_lbracket,
      BRACKET_LEFT_RIGHT: :on_op,
      BRACKET_LEFT_RIGHT_EQUAL: :on_op,
      BRACKET_RIGHT: :on_rbracket,
      CARET: :on_op,
      CARET_EQUAL: :on_op,
      CHARACTER_LITERAL: :on_CHAR,
      CLASS_VARIABLE: :on_cvar,
      COLON: :on_op,
      COLON_COLON: :on_op,
      COMMA: :on_comma,
      COMMENT: :on_comment,
      CONSTANT: :on_const,
      DOT: :on_period,
      DOT_DOT: :on_op,
      DOT_DOT_DOT: :on_op,
      EMBDOC_BEGIN: :on_embdoc_beg,
      EMBDOC_END: :on_embdoc_end,
      EMBDOC_LINE: :on_embdoc,
      EMBEXPR_BEGIN: :on_embexpr_beg,
      EMBEXPR_END: :on_embexpr_end,
      EMBVAR: :on_embvar,
      EOF: :on_eof,
      EQUAL: :on_op,
      EQUAL_EQUAL: :on_op,
      EQUAL_EQUAL_EQUAL: :on_op,
      EQUAL_GREATER: :on_op,
      EQUAL_TILDE: :on_op,
      FLOAT: :on_float,
      FLOAT_IMAGINARY: :on_imaginary,
      FLOAT_RATIONAL: :on_rational,
      FLOAT_RATIONAL_IMAGINARY: :on_imaginary,
      GREATER: :on_op,
      GREATER_EQUAL: :on_op,
      GREATER_GREATER: :on_op,
      GREATER_GREATER_EQUAL: :on_op,
      GLOBAL_VARIABLE: :on_gvar,
      HEREDOC_END: :on_heredoc_end,
      HEREDOC_START: :on_heredoc_beg,
      IDENTIFIER: :on_ident,
      IGNORED_NEWLINE: :on_ignored_nl,
      INTEGER: :on_int,
      INTEGER_IMAGINARY: :on_imaginary,
      INTEGER_RATIONAL: :on_rational,
      INTEGER_RATIONAL_IMAGINARY: :on_imaginary,
      INSTANCE_VARIABLE: :on_ivar,
      INVALID: :INVALID,
      KEYWORD___ENCODING__: :on_kw,
      KEYWORD___LINE__: :on_kw,
      KEYWORD___FILE__: :on_kw,
      KEYWORD_ALIAS: :on_kw,
      KEYWORD_AND: :on_kw,
      KEYWORD_BEGIN: :on_kw,
      KEYWORD_BEGIN_UPCASE: :on_kw,
      KEYWORD_BREAK: :on_kw,
      KEYWORD_CASE: :on_kw,
      KEYWORD_CLASS: :on_kw,
      KEYWORD_DEF: :on_kw,
      KEYWORD_DEFINED: :on_kw,
      KEYWORD_DO: :on_kw,
      KEYWORD_DO_LOOP: :on_kw,
      KEYWORD_ELSE: :on_kw,
      KEYWORD_ELSIF: :on_kw,
      KEYWORD_END: :on_kw,
      KEYWORD_END_UPCASE: :on_kw,
      KEYWORD_ENSURE: :on_kw,
      KEYWORD_FALSE: :on_kw,
      KEYWORD_FOR: :on_kw,
      KEYWORD_IF: :on_kw,
      KEYWORD_IF_MODIFIER: :on_kw,
      KEYWORD_IN: :on_kw,
      KEYWORD_MODULE: :on_kw,
      KEYWORD_NEXT: :on_kw,
      KEYWORD_NIL: :on_kw,
      KEYWORD_NOT: :on_kw,
      KEYWORD_OR: :on_kw,
      KEYWORD_REDO: :on_kw,
      KEYWORD_RESCUE: :on_kw,
      KEYWORD_RESCUE_MODIFIER: :on_kw,
      KEYWORD_RETRY: :on_kw,
      KEYWORD_RETURN: :on_kw,
      KEYWORD_SELF: :on_kw,
      KEYWORD_SUPER: :on_kw,
      KEYWORD_THEN: :on_kw,
      KEYWORD_TRUE: :on_kw,
      KEYWORD_UNDEF: :on_kw,
      KEYWORD_UNLESS: :on_kw,
      KEYWORD_UNLESS_MODIFIER: :on_kw,
      KEYWORD_UNTIL: :on_kw,
      KEYWORD_UNTIL_MODIFIER: :on_kw,
      KEYWORD_WHEN: :on_kw,
      KEYWORD_WHILE: :on_kw,
      KEYWORD_WHILE_MODIFIER: :on_kw,
      KEYWORD_YIELD: :on_kw,
      LABEL: :on_label,
      LABEL_END: :on_label_end,
      LAMBDA_BEGIN: :on_tlambeg,
      LESS: :on_op,
      LESS_EQUAL: :on_op,
      LESS_EQUAL_GREATER: :on_op,
      LESS_LESS: :on_op,
      LESS_LESS_EQUAL: :on_op,
      METHOD_NAME: :on_ident,
      MINUS: :on_op,
      MINUS_EQUAL: :on_op,
      MINUS_GREATER: :on_tlambda,
      NEWLINE: :on_nl,
      NUMBERED_REFERENCE: :on_backref,
      PARENTHESIS_LEFT: :on_lparen,
      PARENTHESIS_LEFT_PARENTHESES: :on_lparen,
      PARENTHESIS_RIGHT: :on_rparen,
      PERCENT: :on_op,
      PERCENT_EQUAL: :on_op,
      PERCENT_LOWER_I: :on_qsymbols_beg,
      PERCENT_LOWER_W: :on_qwords_beg,
      PERCENT_LOWER_X: :on_backtick,
      PERCENT_UPPER_I: :on_symbols_beg,
      PERCENT_UPPER_W: :on_words_beg,
      PIPE: :on_op,
      PIPE_EQUAL: :on_op,
      PIPE_PIPE: :on_op,
      PIPE_PIPE_EQUAL: :on_op,
      PLUS: :on_op,
      PLUS_EQUAL: :on_op,
      QUESTION_MARK: :on_op,
      RATIONAL_FLOAT: :on_rational,
      RATIONAL_INTEGER: :on_rational,
      REGEXP_BEGIN: :on_regexp_beg,
      REGEXP_END: :on_regexp_end,
      SEMICOLON: :on_semicolon,
      SLASH: :on_op,
      SLASH_EQUAL: :on_op,
      STAR: :on_op,
      STAR_EQUAL: :on_op,
      STAR_STAR: :on_op,
      STAR_STAR_EQUAL: :on_op,
      STRING_BEGIN: :on_tstring_beg,
      STRING_CONTENT: :on_tstring_content,
      STRING_END: :on_tstring_end,
      SYMBOL_BEGIN: :on_symbeg,
      TILDE: :on_op,
      UAMPERSAND: :on_op,
      UCOLON_COLON: :on_op,
      UDOT_DOT: :on_op,
      UDOT_DOT_DOT: :on_op,
      UMINUS: :on_op,
      UMINUS_NUM: :on_op,
      UPLUS: :on_op,
      USTAR: :on_op,
      USTAR_STAR: :on_op,
      WORDS_SEP: :on_words_sep,
      "__END__": :on___end__
    }.freeze

    # A heredoc in this case is a list of tokens that belong to the body of the
    # heredoc that should be appended onto the list of tokens when the heredoc
    # closes.
    module Heredoc # :nodoc:
      # Heredocs that are no dash or tilde heredocs are just a list of tokens.
      # We need to keep them around so that we can insert them in the correct
      # order back into the token stream and set the state of the last token to
      # the state that the heredoc was opened in.
      class PlainHeredoc # :nodoc:
        attr_reader :tokens #: Array[lex_compat_token]

        #: () -> void
        def initialize
          @tokens = []
        end

        #: (lex_compat_token token) -> void
        def <<(token)
          tokens << token
        end

        #: () -> Array[lex_compat_token]
        def to_a
          tokens
        end
      end

      # Dash heredocs are a little more complicated. They are a list of tokens
      # that need to be split on "\\\n" to mimic Ripper's behavior. We also need
      # to keep track of the state that the heredoc was opened in.
      class DashHeredoc # :nodoc:
        attr_reader :split #: bool
        attr_reader :tokens #: Array[lex_compat_token]

        #: (bool split) -> void
        def initialize(split)
          @split = split
          @tokens = []
        end

        #: (lex_compat_token token) -> void
        def <<(token)
          tokens << token
        end

        #: () -> Array[lex_compat_token]
        def to_a
          embexpr_balance = 0

          tokens.each_with_object([]) do |token, results| #$ Array[lex_compat_token]
            case token[1]
            when :on_embexpr_beg
              embexpr_balance += 1
              results << token
            when :on_embexpr_end
              embexpr_balance -= 1
              results << token
            when :on_tstring_content
              if embexpr_balance == 0
                lineno = token[0][0]
                column = token[0][1]

                if split
                  # Split on "\\\n" to mimic Ripper's behavior. Use a lookbehind
                  # to keep the delimiter in the result.
                  token[2].split(/(?<=[^\\]\\\n)|(?<=[^\\]\\\r\n)/).each_with_index do |value, index|
                    column = 0 if index > 0
                    results << [[lineno, column], :on_tstring_content, value, token[3]]
                    lineno += value.count("\n")
                  end
                else
                  results << token
                end
              else
                results << token
              end
            else
              results << token
            end
          end
        end
      end

      # Heredocs that are dedenting heredocs are a little more complicated.
      # Ripper outputs on_ignored_sp tokens for the whitespace that is being
      # removed from the output. prism only modifies the node itself and keeps
      # the token the same. This simplifies prism, but makes comparing against
      # Ripper much harder because there is a length mismatch.
      #
      # Fortunately, we already have to pull out the heredoc tokens in order to
      # insert them into the stream in the correct order. As such, we can do
      # some extra manipulation on the tokens to make them match Ripper's
      # output by mirroring the dedent logic that Ripper uses.
      class DedentingHeredoc # :nodoc:
        TAB_WIDTH = 8

        attr_reader :tokens #: Array[lex_compat_token]
        attr_reader :dedent_next #: bool
        attr_reader :dedent #: Integer?
        attr_reader :embexpr_balance #: Integer
        # @rbs @ended_on_newline: bool

        #: () -> void
        def initialize
          @tokens = []
          @dedent_next = true
          @dedent = nil
          @embexpr_balance = 0
          @ended_on_newline = false
        end

        # As tokens are coming in, we track the minimum amount of common leading
        # whitespace on plain string content tokens. This allows us to later
        # remove that amount of whitespace from the beginning of each line.
        #
        #: (lex_compat_token token) -> void
        def <<(token)
          case token[1]
          when :on_embexpr_beg, :on_heredoc_beg
            @embexpr_balance += 1
            @dedent = 0 if @dedent_next && @ended_on_newline
          when :on_embexpr_end, :on_heredoc_end
            @embexpr_balance -= 1
          when :on_tstring_content
            if embexpr_balance == 0
              line = token[2]

              if dedent_next && !(line.strip.empty? && line.end_with?("\n"))
                leading = line[/\A(\s*)\n?/, 1] #: String
                next_dedent = 0

                leading.each_char do |char|
                  if char == "\t"
                    next_dedent = next_dedent - (next_dedent % TAB_WIDTH) + TAB_WIDTH
                  else
                    next_dedent += 1
                  end
                end

                @dedent = [dedent, next_dedent].compact.min
                @dedent_next = true
                @ended_on_newline = line.end_with?("\n")
                tokens << token
                return
              end
            end
          end

          @dedent_next = token[1] == :on_tstring_content && embexpr_balance == 0
          @ended_on_newline = false
          tokens << token
        end

        #: () -> Array[lex_compat_token]
        def to_a
          # If every line in the heredoc is blank, we still need to split up the
          # string content token into multiple tokens.
          if dedent.nil?
            results = [] #: Array[lex_compat_token]
            embexpr_balance = 0

            tokens.each do |token|
              case token[1]
              when :on_embexpr_beg, :on_heredoc_beg
                embexpr_balance += 1
                results << token
              when :on_embexpr_end, :on_heredoc_end
                embexpr_balance -= 1
                results << token
              when :on_tstring_content
                if embexpr_balance == 0
                  lineno = token[0][0]
                  column = token[0][1]

                  token[2].split(/(?<=\n)/).each_with_index do |value, index|
                    column = 0 if index > 0
                    results << [[lineno, column], :on_tstring_content, value, token[3]]
                    lineno += 1
                  end
                else
                  results << token
                end
              else
                results << token
              end
            end

            return results
          end

          # If the minimum common whitespace is 0, then we need to concatenate
          # string nodes together that are immediately adjacent.
          if dedent == 0
            results = [] #: Array[lex_compat_token]
            embexpr_balance = 0

            index = 0
            max_index = tokens.length

            while index < max_index
              token = tokens[index]
              results << token
              index += 1

              case token[1]
              when :on_embexpr_beg, :on_heredoc_beg
                embexpr_balance += 1
              when :on_embexpr_end, :on_heredoc_end
                embexpr_balance -= 1
              when :on_tstring_content
                if embexpr_balance == 0
                  while index < max_index && tokens[index][1] == :on_tstring_content && !token[2].match?(/\\\r?\n\z/)
                    token[2] << tokens[index][2]
                    index += 1
                  end
                end
              end
            end

            return results
          end

          # Otherwise, we're going to run through each token in the list and
          # insert on_ignored_sp tokens for the amount of dedent that we need to
          # perform. We also need to remove the dedent from the beginning of
          # each line of plain string content tokens.
          results = [] #: Array[lex_compat_token]
          dedent_next = true
          embexpr_balance = 0

          tokens.each do |token|
            # Notice that the structure of this conditional largely matches the
            # whitespace calculation we performed above. This is because
            # checking if the subsequent token needs to be dedented is common to
            # both the dedent calculation and the ignored_sp insertion.
            case token[1]
            when :on_embexpr_beg
              embexpr_balance += 1
              results << token
            when :on_embexpr_end
              embexpr_balance -= 1
              results << token
            when :on_tstring_content
              if embexpr_balance == 0
                # Here we're going to split the string on newlines, but maintain
                # the newlines in the resulting array. We'll do that with a look
                # behind assertion.
                splits = token[2].split(/(?<=\n)/)
                index = 0

                while index < splits.length
                  line = splits[index]
                  lineno = token[0][0] + index
                  column = token[0][1]

                  # Blank lines do not count toward common leading whitespace
                  # calculation and do not need to be dedented.
                  if dedent_next || index > 0
                    column = 0
                  end

                  # If the dedent is 0 and we're not supposed to dedent the next
                  # line or this line doesn't start with whitespace, then we
                  # should concatenate the rest of the string to match ripper.
                  if dedent == 0 && (!dedent_next || !line.start_with?(/\s/))
                    unjoined = splits[index..] #: Array[String]
                    line = unjoined.join
                    index = splits.length
                  end

                  # If we are supposed to dedent this line or if this is not the
                  # first line of the string and this line isn't entirely blank,
                  # then we need to insert an on_ignored_sp token and remove the
                  # dedent from the beginning of the line.
                  if (dedent > 0) && (dedent_next || index > 0)
                    deleting = 0
                    deleted_chars = [] #: Array[String]

                    # Gather up all of the characters that we're going to
                    # delete, stopping when you hit a character that would put
                    # you over the dedent amount.
                    line.each_char.with_index do |char, i|
                      case char
                      when "\r"
                        if line[i + 1] == "\n"
                          break
                        end
                      when "\n"
                        break
                      when "\t"
                        deleting = deleting - (deleting % TAB_WIDTH) + TAB_WIDTH
                      else
                        deleting += 1
                      end

                      break if deleting > dedent
                      deleted_chars << char
                    end

                    # If we have something to delete, then delete it from the
                    # string and insert an on_ignored_sp token.
                    if deleted_chars.any?
                      ignored = deleted_chars.join
                      line.delete_prefix!(ignored)

                      results << [[lineno, 0], :on_ignored_sp, ignored, token[3]]
                      column = ignored.length
                    end
                  end

                  results << [[lineno, column], token[1], line, token[3]] unless line.empty?
                  index += 1
                end
              else
                results << token
              end
            else
              results << token
            end

            dedent_next =
              ((token[1] == :on_tstring_content) || (token[1] == :on_heredoc_end)) &&
              embexpr_balance == 0
          end

          results
        end
      end

      # Here we will split between the two types of heredocs and return the
      # object that will store their tokens.
      #--
      #: (lex_compat_token opening) -> (PlainHeredoc | DashHeredoc | DedentingHeredoc)
      def self.build(opening)
        case opening[2][2]
        when "~"
          DedentingHeredoc.new
        when "-"
          DashHeredoc.new(opening[2][3] != "'")
        else
          PlainHeredoc.new
        end
      end
    end

    private_constant :Heredoc

    # In previous versions of Ruby, Ripper wouldn't flush the bom before the
    # first token, so we had to have a hack in place to account for that.
    BOM_FLUSHED = RUBY_VERSION >= "3.3.0"
    private_constant :BOM_FLUSHED

    attr_reader :options #: Hash[Symbol, untyped]
    # @rbs @source: String

    #: (String source, **untyped options) -> void
    def initialize(source, **options)
      @source = source
      @options = options
    end

    #: () -> Result
    def result
      tokens = [] #: Array[lex_compat_token]

      state = :default
      heredoc_stack = [[]] #: Array[Array[Heredoc::PlainHeredoc | Heredoc::DashHeredoc | Heredoc::DedentingHeredoc]]

      result = Prism.lex(@source, **options)
      source = result.source
      result_value = result.value
      previous_state = nil #: Translation::Ripper::Lexer::State?
      last_heredoc_end = nil #: Integer?
      eof_token = nil #: Token?

      bom = source.slice(0, 3) == "\xEF\xBB\xBF"

      result_value.each_with_index do |(prism_token, prism_state), index|
        lineno = prism_token.location.start_line
        column = prism_token.location.start_column

        event = RIPPER.fetch(prism_token.type)
        value = prism_token.value
        lex_state = Translation::Ripper::Lexer::State[prism_state]

        # If there's a UTF-8 byte-order mark as the start of the file, then for
        # certain tokens ripper sets the first token back by 3 bytes. It also
        # keeps the byte order mark in the first token's value. This is weird,
        # and I don't want to mirror that in our parser. So instead, we'll match
        # up the columns and values here.
        if bom && lineno == 1
          column -= 3

          if index == 0 && column == 0 && !BOM_FLUSHED
            flushed =
              case prism_token.type
              when :BACK_REFERENCE, :INSTANCE_VARIABLE, :CLASS_VARIABLE,
                  :GLOBAL_VARIABLE, :NUMBERED_REFERENCE, :PERCENT_LOWER_I,
                  :PERCENT_LOWER_X, :PERCENT_LOWER_W, :PERCENT_UPPER_I,
                  :PERCENT_UPPER_W, :STRING_BEGIN
                true
              when :REGEXP_BEGIN, :SYMBOL_BEGIN
                value.start_with?("%")
              else
                false
              end

            unless flushed
              column -= 3
              value.prepend(String.new("\xEF\xBB\xBF", encoding: value.encoding))
            end
          end
        end

        lex_compat_token =
          case event
          when :on___end__
            # Ripper doesn't include the rest of the token in the event, so we need to
            # trim it down to just the content on the first line.
            value = value[0..value.index("\n")] #: String
            [[lineno, column], event, value, lex_state]
          when :on_comment
            [[lineno, column], event, value, lex_state]
          when :on_heredoc_end
            # Heredoc end tokens can be emitted in an odd order, so we don't
            # want to bother comparing the state on them.
            last_heredoc_end = prism_token.location.end_offset
            [[lineno, column], event, value, lex_state]
          when :on_embexpr_end
            [[lineno, column], event, value, lex_state]
          when :on_words_sep
            # Ripper emits one token each per line.
            value.each_line.with_index do |line, index|
              if index > 0
                lineno += 1
                column = 0
              end
              tokens << [[lineno, column], event, line, lex_state]
            end
            tokens.pop #: lex_compat_token
          when :on_regexp_end
            # On regex end, Ripper scans and then sets end state, so the ripper
            # lexed output is begin, when it should be end. prism sets lex state
            # correctly to end state, but we want to be able to compare against
            # Ripper's lexed state. So here, if it's a regexp end token, we
            # output the state as the previous state, solely for the sake of
            # comparison.
            previous_token = result_value[index - 1][0]
            lex_state =
              if RIPPER.fetch(previous_token.type) == :on_embexpr_end
                # If the previous token is embexpr_end, then we have to do even
                # more processing. The end of an embedded expression sets the
                # state to the state that it had at the beginning of the
                # embedded expression. So we have to go and find that state and
                # set it here.
                counter = 1
                current_index = index - 1

                until counter == 0
                  current_index -= 1
                  current_event = RIPPER.fetch(result_value[current_index][0].type)
                  counter += { on_embexpr_beg: -1, on_embexpr_end: 1 }[current_event] || 0
                end

                Translation::Ripper::Lexer::State[result_value[current_index][1]]
              else
                previous_state
              end

            [[lineno, column], event, value, lex_state]
          when :on_eof
            eof_token = prism_token
            previous_token = result_value[index - 1][0]

            # If we're at the end of the file and the previous token was a
            # comment and there is still whitespace after the comment, then
            # Ripper will append a on_nl token (even though there isn't
            # necessarily a newline). We mirror that here.
            if previous_token.type == :COMMENT
              # If the comment is at the start of a heredoc: <<HEREDOC # comment
              # then the comment's end_offset is up near the heredoc_beg.
              # This is not the correct offset to use for figuring out if
              # there is trailing whitespace after the last token.
              # Use the greater offset of the two to determine the start of
              # the trailing whitespace.
              start_offset = [previous_token.location.end_offset, last_heredoc_end].compact.max
              end_offset = prism_token.location.start_offset

              if start_offset < end_offset
                if bom
                  start_offset += 3
                  end_offset += 3
                end

                tokens << [[lineno, 0], :on_nl, source.slice(start_offset, end_offset - start_offset), lex_state]
              end
            end

            [[lineno, column], event, value, lex_state]
          else
            [[lineno, column], event, value, lex_state]
          end #: lex_compat_token

        previous_state = lex_state

        # The order in which tokens appear in our lexer is different from the
        # order that they appear in Ripper. When we hit the declaration of a
        # heredoc in prism, we skip forward and lex the rest of the content of
        # the heredoc before going back and lexing at the end of the heredoc
        # identifier.
        #
        # To match up to ripper, we keep a small state variable around here to
        # track whether we're in the middle of a heredoc or not. In this way we
        # can shuffle around the token to match Ripper's output.
        case state
        when :default
          # The default state is when there are no heredocs at all. In this
          # state we can append the token to the list of tokens and move on.
          tokens << lex_compat_token

          # If we get the declaration of a heredoc, then we open a new heredoc
          # and move into the heredoc_opened state.
          if event == :on_heredoc_beg
            state = :heredoc_opened
            heredoc_stack.last << Heredoc.build(lex_compat_token)
          end
        when :heredoc_opened
          # The heredoc_opened state is when we've seen the declaration of a
          # heredoc and are now lexing the body of the heredoc. In this state we
          # push tokens onto the most recently created heredoc.
          heredoc_stack.last.last << lex_compat_token

          case event
          when :on_heredoc_beg
            # If we receive a heredoc declaration while lexing the body of a
            # heredoc, this means we have nested heredocs. In this case we'll
            # push a new heredoc onto the stack and stay in the heredoc_opened
            # state since we're now lexing the body of the new heredoc.
            heredoc_stack << [Heredoc.build(lex_compat_token)]
          when :on_heredoc_end
            # If we receive the end of a heredoc, then we're done lexing the
            # body of the heredoc. In this case we now have a completed heredoc
            # but need to wait for the next newline to push it into the token
            # stream.
            state = :heredoc_closed
          end
        when :heredoc_closed
          if %i[on_nl on_ignored_nl on_comment].include?(event) || ((event == :on_tstring_content) && value.end_with?("\n"))
            if heredoc_stack.size > 1
              flushing = heredoc_stack.pop #: Array[Heredoc::PlainHeredoc | Heredoc::DashHeredoc | Heredoc::DedentingHeredoc]
              heredoc_stack.last.last << lex_compat_token

              flushing.each do |heredoc|
                heredoc.to_a.each do |flushed_token|
                  heredoc_stack.last.last << flushed_token
                end
              end

              state = :heredoc_opened
              next
            end
          elsif event == :on_heredoc_beg
            tokens << lex_compat_token
            state = :heredoc_opened
            heredoc_stack.last << Heredoc.build(lex_compat_token)
            next
          elsif heredoc_stack.size > 1
            heredoc_stack[-2].last << lex_compat_token
            next
          end

          heredoc_stack.last.each do |heredoc|
            tokens.concat(heredoc.to_a)
          end

          heredoc_stack.last.clear
          state = :default

          tokens << lex_compat_token
        end
      end

      # Drop the EOF token from the list. The EOF token may not be
      # present if the source was syntax invalid
      if tokens.dig(-1, 1) == :on_eof
        tokens = tokens[0...-1] #: Array[lex_compat_token]
      end

      # We sort by location because Ripper.lex sorts.
      tokens.sort_by! do |token|
        line, column = token[0]
        source.byte_offset(line, column)
      end

      tokens = post_process_tokens(tokens, source, result.data_loc, bom, eof_token)

      Result.new(tokens, result.comments, result.magic_comments, result.data_loc, result.errors, result.warnings, source)
    end

    private

    #: (Array[lex_compat_token] tokens, Source source, Location? data_loc, bool bom, Token? eof_token) -> Array[lex_compat_token]
    def post_process_tokens(tokens, source, data_loc, bom, eof_token)
      new_tokens = [] #: Array[lex_compat_token]

      prev_token_state = Translation::Ripper::Lexer::State[Translation::Ripper::EXPR_BEG]
      prev_token_end = bom ? 3 : 0

      tokens.each do |token|
        # Skip missing heredoc ends.
        next if token[1] == :on_heredoc_end && token[2] == ""

        # Add :on_sp tokens.
        line, column = token[0]
        start_offset = source.byte_offset(line, column)

        # Ripper reports columns on line 1 without counting the BOM, so we
        # adjust to get the real offset
        start_offset += 3 if line == 1 && bom

        if start_offset > prev_token_end
          sp_value = source.slice(prev_token_end, start_offset - prev_token_end)
          sp_line = source.line(prev_token_end)
          sp_column = source.column(prev_token_end)
          # Ripper reports columns on line 1 without counting the BOM
          sp_column -= 3 if sp_line == 1 && bom
          continuation_index = sp_value.byteindex("\\")

          # ripper emits up to three :on_sp tokens when line continuations are used
          if continuation_index
            next_whitespace_index = continuation_index + 1
            next_whitespace_index += 1 if sp_value.byteslice(next_whitespace_index) == "\r"
            next_whitespace_index += 1
            first_whitespace = sp_value[0...continuation_index] #: String
            continuation = sp_value[continuation_index...next_whitespace_index] #: String
            second_whitespace = sp_value[next_whitespace_index..] || ""

            new_tokens << [[sp_line, sp_column], :on_sp, first_whitespace, prev_token_state] unless first_whitespace.empty?
            new_tokens << [[sp_line, sp_column + continuation_index], :on_sp, continuation, prev_token_state]
            new_tokens << [[sp_line + 1, 0], :on_sp, second_whitespace, prev_token_state] unless second_whitespace.empty?
          else
            new_tokens << [[sp_line, sp_column], :on_sp, sp_value, prev_token_state]
          end
        end

        new_tokens << token
        prev_token_state = token[3]
        prev_token_end = start_offset + token[2].bytesize
      end

      if !data_loc && eof_token # no trailing :on_sp with __END__ as it is always preceded by :on_nl
        end_offset = eof_token.location.end_offset
        if prev_token_end < end_offset
          new_tokens << [
            [source.line(prev_token_end), source.column(prev_token_end)],
            :on_sp,
            source.slice(prev_token_end, end_offset - prev_token_end),
            prev_token_state
          ]
        end
      end

      new_tokens
    end
  end

  private_constant :LexCompat
end
