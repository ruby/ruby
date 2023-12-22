require 'lrama/grammar/parameterizing_rules/builder'

module Lrama
  class Grammar
    class RuleBuilder
      attr_accessor :lhs, :lhs_tag, :line
      attr_reader :rhs, :user_code, :precedence_sym

      def initialize(rule_counter, midrule_action_counter, position_in_original_rule_rhs = nil, skip_preprocess_references: false)
        @rule_counter = rule_counter
        @midrule_action_counter = midrule_action_counter
        @position_in_original_rule_rhs = position_in_original_rule_rhs
        @skip_preprocess_references = skip_preprocess_references

        @lhs = nil
        @rhs = []
        @lhs_tag = nil
        @user_code = nil
        @precedence_sym = nil
        @line = nil
        @rule_builders_for_derived_rules = []
      end

      def add_rhs(rhs)
        if !@line
          @line = rhs.line
        end

        flush_user_code

        @rhs << rhs
      end

      def user_code=(user_code)
        if !@line
          @line = user_code.line
        end

        flush_user_code

        @user_code = user_code
      end

      def precedence_sym=(precedence_sym)
        flush_user_code

        @precedence_sym = precedence_sym
      end

      def complete_input
        freeze_rhs
      end

      def setup_rules
        preprocess_references unless @skip_preprocess_references
        process_rhs
        build_rules
      end

      def parameterizing_rules
        @parameterizing_rules
      end

      def midrule_action_rules
        @midrule_action_rules
      end

      def rules
        @rules
      end

      private

      def freeze_rhs
        @rhs.freeze
      end

      def preprocess_references
        numberize_references
      end

      def build_rules
        tokens = @replaced_rhs

        rule = Rule.new(
          id: @rule_counter.increment, _lhs: lhs, _rhs: tokens, token_code: user_code,
          position_in_original_rule_rhs: @position_in_original_rule_rhs, precedence_sym: precedence_sym, lineno: line
        )
        @rules = [rule]
        @midrule_action_rules = @rule_builders_for_derived_rules.map do |rule_builder|
          rule_builder.rules
        end.flatten
        @midrule_action_rules.each do |r|
          r.original_rule = rule
        end
      end

      # rhs is a mixture of variety type of tokens like `Ident`, `Parameterizing`, `UserCode` and so on.
      # `#process_rhs` replaces some kind of tokens to `Ident` so that all `@replaced_rhs` are `Ident` or `Char`.
      def process_rhs
        return if @replaced_rhs

        @replaced_rhs = []
        @parameterizing_rules = []

        rhs.each_with_index do |token, i|
          case token
          when Lrama::Lexer::Token::Char
            @replaced_rhs << token
          when Lrama::Lexer::Token::Ident
            @replaced_rhs << token
          when Lrama::Lexer::Token::Parameterizing
            parameterizing = ParameterizingRules::Builder.new(token, @rule_counter, @lhs_tag, user_code, precedence_sym, line)
            parameterizing.build.each do |r|
              @parameterizing_rules << r
            end
            @replaced_rhs << parameterizing.build_token
          when Lrama::Lexer::Token::UserCode
            prefix = token.referred ? "@" : "$@"
            new_token = Lrama::Lexer::Token::Ident.new(s_value: prefix + @midrule_action_counter.increment.to_s)
            @replaced_rhs << new_token

            rule_builder = RuleBuilder.new(@rule_counter, @midrule_action_counter, i, skip_preprocess_references: true)
            rule_builder.lhs = new_token
            rule_builder.user_code = token
            rule_builder.complete_input
            rule_builder.setup_rules

            @rule_builders_for_derived_rules << rule_builder
          else
            raise "Unexpected token. #{token}"
          end
        end
      end

      def numberize_references
        # Bison n'th component is 1-origin
        (rhs + [user_code]).compact.each.with_index(1) do |token, i|
          next unless token.is_a?(Lrama::Lexer::Token::UserCode)

          token.references.each do |ref|
            ref_name = ref.name
            if ref_name && ref_name != '$'
              if lhs.referred_by?(ref_name)
                ref.name = '$'
              else
                candidates = rhs.each_with_index.select {|token, i| token.referred_by?(ref_name) }

                raise "Referring symbol `#{ref_name}` is duplicated. #{token}" if candidates.size >= 2
                raise "Referring symbol `#{ref_name}` is not found. #{token}" unless referring_symbol = candidates.first

                ref.index = referring_symbol[1] + 1
              end
            end

            # TODO: Need to check index of @ too?
            next if ref.type == :at

            if ref.index
              # TODO: Prohibit $0 even so Bison allows it?
              # See: https://www.gnu.org/software/bison/manual/html_node/Actions.html
              raise "Can not refer following component. #{ref.index} >= #{i}. #{token}" if ref.index >= i
              rhs[ref.index - 1].referred = true
            end
          end
        end
      end

      def flush_user_code
        if c = @user_code
          @rhs << c
          @user_code = nil
        end
      end
    end
  end
end
