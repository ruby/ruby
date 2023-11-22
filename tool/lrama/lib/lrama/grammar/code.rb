require "forwardable"

module Lrama
  class Grammar
    class Code < Struct.new(:type, :token_code, keyword_init: true)
      extend Forwardable

      def_delegators "token_code", :s_value, :line, :column, :references

      # $$, $n, @$, @n are translated to C code
      def translated_code
        t_code = s_value.dup

        references.reverse.each do |ref|
          first_column = ref.first_column
          last_column = ref.last_column

          str = reference_to_c(ref)

          t_code[first_column..last_column] = str
        end

        return t_code
      end

      private

      def reference_to_c(ref)
        raise NotImplementedError.new("#reference_to_c is not implemented")
      end
    end
  end
end

require "lrama/grammar/code/initial_action_code"
require "lrama/grammar/code/no_reference_code"
require "lrama/grammar/code/printer_code"
require "lrama/grammar/code/rule_action"
