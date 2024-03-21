require "forwardable"
require "lrama/grammar/code/destructor_code"
require "lrama/grammar/code/initial_action_code"
require "lrama/grammar/code/no_reference_code"
require "lrama/grammar/code/printer_code"
require "lrama/grammar/code/rule_action"

module Lrama
  class Grammar
    class Code
      extend Forwardable

      def_delegators "token_code", :s_value, :line, :column, :references

      attr_reader :type, :token_code

      def initialize(type:, token_code:)
        @type = type
        @token_code = token_code
      end

      def ==(other)
        self.class == other.class &&
        self.type == other.type &&
        self.token_code == other.token_code
      end

      # $$, $n, @$, @n are translated to C code
      def translated_code
        t_code = s_value.dup

        references.reverse_each do |ref|
          first_column = ref.first_column
          last_column = ref.last_column

          str = reference_to_c(ref)

          t_code[first_column...last_column] = str
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
