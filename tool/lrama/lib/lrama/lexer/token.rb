require 'lrama/lexer/token/type'

module Lrama
  class Lexer
    class Token

      attr_accessor :line, :column, :referred
      # For User_code
      attr_accessor :references

      def to_s
        "#{super} line: #{line}, column: #{column}"
      end

      def referred_by?(string)
        [self.s_value, self.alias].include?(string)
      end

      def ==(other)
        self.class == other.class && self.type == other.type && self.s_value == other.s_value
      end

      def numberize_references(lhs, rhs)
        self.references.map! {|ref|
          ref_name = ref[1]
          if ref_name.is_a?(::String) && ref_name != '$'
            value =
              if lhs.referred_by?(ref_name)
                '$'
              else
                index = rhs.find_index {|token| token.referred_by?(ref_name) }

                if index
                  index + 1
                else
                  raise "'#{ref_name}' is invalid name."
                end
              end
            [ref[0], value, ref[2], ref[3], ref[4]]
          else
            ref
          end
        }
      end

      @i = 0
      @types = []

      def self.define_type(name)
        type = Type.new(id: @i, name: name.to_s)
        const_set(name, type)
        @types << type
        @i += 1
      end

      # Token types
      define_type(:P_expect)         # %expect
      define_type(:P_define)         # %define
      define_type(:P_printer)        # %printer
      define_type(:P_error_token)    # %error-token
      define_type(:P_lex_param)      # %lex-param
      define_type(:P_parse_param)    # %parse-param
      define_type(:P_initial_action) # %initial-action
      define_type(:P_union)          # %union
      define_type(:P_token)          # %token
      define_type(:P_type)           # %type
      define_type(:P_nonassoc)       # %nonassoc
      define_type(:P_left)           # %left
      define_type(:P_right)          # %right
      define_type(:P_precedence)     # %precedence
      define_type(:P_prec)           # %prec
      define_type(:User_code)        # { ... }
      define_type(:Tag)              # <int>
      define_type(:Number)           # 0
      define_type(:Ident_Colon)      # k_if:, k_if  : (spaces can be there)
      define_type(:Ident)            # api.pure, tNUMBER
      define_type(:Named_Ref)        # [foo]
      define_type(:Semicolon)        # ;
      define_type(:Bar)              # |
      define_type(:String)           # "str"
      define_type(:Char)             # '+'
    end
  end
end
