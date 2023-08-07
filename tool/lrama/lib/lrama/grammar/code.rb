require "forwardable"

module Lrama
  class Grammar
    class Code < Struct.new(:type, :token_code, keyword_init: true)
      extend Forwardable

      def_delegators "token_code", :s_value, :line, :column, :references

      # $$, $n, @$, @n is translated to C code
      def translated_code
        case type
        when :user_code
          translated_user_code
        when :initial_action
          translated_initial_action_code
        end
      end

      # * ($1) error
      # * ($$) *yyvaluep
      # * (@1) error
      # * (@$) *yylocationp
      def translated_printer_code(tag)
        t_code = s_value.dup

        references.reverse.each do |ref|
          first_column = ref.first_column
          last_column = ref.last_column

          case
          when ref.value == "$" && ref.type == :dollar # $$
            # Omit "<>"
            member = tag.s_value[1..-2]
            str = "((*yyvaluep).#{member})"
          when ref.value == "$" && ref.type == :at # @$
            str = "(*yylocationp)"
          when ref.type == :dollar # $n
            raise "$#{ref.value} can not be used in %printer."
          when ref.type == :at # @n
            raise "@#{ref.value} can not be used in %printer."
          else
            raise "Unexpected. #{self}, #{ref}"
          end

          t_code[first_column..last_column] = str
        end

        return t_code
      end
      alias :translated_error_token_code :translated_printer_code


      private

      # * ($1) yyvsp[i]
      # * ($$) yyval
      # * (@1) yylsp[i]
      # * (@$) yyloc
      def translated_user_code
        t_code = s_value.dup

        references.reverse.each do |ref|
          first_column = ref.first_column
          last_column = ref.last_column

          case
          when ref.value == "$" && ref.type == :dollar # $$
            # Omit "<>"
            member = ref.tag.s_value[1..-2]
            str = "(yyval.#{member})"
          when ref.value == "$" && ref.type == :at # @$
            str = "(yyloc)"
          when ref.type == :dollar # $n
            i = -ref.position_in_rhs + ref.value
            # Omit "<>"
            member = ref.tag.s_value[1..-2]
            str = "(yyvsp[#{i}].#{member})"
          when ref.type == :at # @n
            i = -ref.position_in_rhs + ref.value
            str = "(yylsp[#{i}])"
          else
            raise "Unexpected. #{self}, #{ref}"
          end

          t_code[first_column..last_column] = str
        end

        return t_code
      end

      # * ($1) error
      # * ($$) yylval
      # * (@1) error
      # * (@$) yylloc
      def translated_initial_action_code
        t_code = s_value.dup

        references.reverse.each do |ref|
          first_column = ref.first_column
          last_column = ref.last_column

          case
          when ref.value == "$" && ref.type == :dollar # $$
            str = "yylval"
          when ref.value == "$" && ref.type == :at # @$
            str = "yylloc"
          when ref.type == :dollar # $n
            raise "$#{ref.value} can not be used in initial_action."
          when ref.type == :at # @n
            raise "@#{ref.value} can not be used in initial_action."
          else
            raise "Unexpected. #{self}, #{ref}"
          end

          t_code[first_column..last_column] = str
        end

        return t_code
      end
    end
  end
end
