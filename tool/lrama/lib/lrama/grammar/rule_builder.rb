module Lrama
  class Grammar
    class RuleBuilder
      attr_accessor :lhs, :line
      attr_reader :lhs_tag, :rhs, :user_code, :precedence_sym

      def initialize(rule_counter, midrule_action_counter, position_in_original_rule_rhs = nil, lhs_tag: nil, skip_preprocess_references: false)
        @rule_counter = rule_counter
        @midrule_action_counter = midrule_action_counter
        @position_in_original_rule_rhs = position_in_original_rule_rhs
        @skip_preprocess_references = skip_preprocess_references

        @lhs = nil
        @lhs_tag = lhs_tag
        @rhs = []
        @user_code = nil
        @precedence_sym = nil
        @line = nil
        @rules = []
        @rule_builders_for_parameterizing_rules = []
        @rule_builders_for_derived_rules = []
        @rule_builders_for_inline_rules = []
        @parameterizing_rules = []
        @inline_rules = []
        @midrule_action_rules = []
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
          @line = user_code&.line
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

      def setup_rules(parameterizing_rule_resolver)
        preprocess_references unless @skip_preprocess_references
        if rhs.any? { |token| parameterizing_rule_resolver.find_inline(token) }
          resolve_inline(parameterizing_rule_resolver)
        else
          process_rhs(parameterizing_rule_resolver)
        end
        build_rules
      end

      def rules
        @parameterizing_rules + @inline_rules + @midrule_action_rules + @rules
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

        if tokens
          rule = Rule.new(
            id: @rule_counter.increment, _lhs: lhs, _rhs: tokens, lhs_tag: lhs_tag, token_code: user_code,
            position_in_original_rule_rhs: @position_in_original_rule_rhs, precedence_sym: precedence_sym, lineno: line
          )
          @rules = [rule]
          @parameterizing_rules = @rule_builders_for_parameterizing_rules.map do |rule_builder|
            rule_builder.rules
          end.flatten
          @midrule_action_rules = @rule_builders_for_derived_rules.map do |rule_builder|
            rule_builder.rules
          end.flatten
          @midrule_action_rules.each do |r|
            r.original_rule = rule
          end
        else
          @inline_rules = @rule_builders_for_inline_rules.map do |rule_builder|
            rule_builder.rules
          end.flatten
        end
      end

      # rhs is a mixture of variety type of tokens like `Ident`, `InstantiateRule`, `UserCode` and so on.
      # `#process_rhs` replaces some kind of tokens to `Ident` so that all `@replaced_rhs` are `Ident` or `Char`.
      def process_rhs(parameterizing_rule_resolver)
        return if @replaced_rhs

        @replaced_rhs = []

        rhs.each_with_index do |token, i|
          case token
          when Lrama::Lexer::Token::Char
            @replaced_rhs << token
          when Lrama::Lexer::Token::Ident
            @replaced_rhs << token
          when Lrama::Lexer::Token::InstantiateRule
            parameterizing_rule = parameterizing_rule_resolver.find_rule(token)
            raise "Unexpected token. #{token}" unless parameterizing_rule

            bindings = Binding.new(parameterizing_rule, token.args)
            lhs_s_value = lhs_s_value(token, bindings)
            if (created_lhs = parameterizing_rule_resolver.created_lhs(lhs_s_value))
              @replaced_rhs << created_lhs
            else
              lhs_token = Lrama::Lexer::Token::Ident.new(s_value: lhs_s_value, location: token.location)
              @replaced_rhs << lhs_token
              parameterizing_rule_resolver.created_lhs_list << lhs_token
              parameterizing_rule.rhs_list.each do |r|
                rule_builder = RuleBuilder.new(@rule_counter, @midrule_action_counter, lhs_tag: token.lhs_tag || parameterizing_rule.tag)
                rule_builder.lhs = lhs_token
                r.symbols.each { |sym| rule_builder.add_rhs(bindings.resolve_symbol(sym)) }
                rule_builder.line = line
                rule_builder.precedence_sym = r.precedence_sym
                rule_builder.user_code = r.resolve_user_code(bindings)
                rule_builder.complete_input
                rule_builder.setup_rules(parameterizing_rule_resolver)
                @rule_builders_for_parameterizing_rules << rule_builder
              end
            end
          when Lrama::Lexer::Token::UserCode
            prefix = token.referred ? "@" : "$@"
            tag = token.tag || lhs_tag
            new_token = Lrama::Lexer::Token::Ident.new(s_value: prefix + @midrule_action_counter.increment.to_s)
            @replaced_rhs << new_token

            rule_builder = RuleBuilder.new(@rule_counter, @midrule_action_counter, i, lhs_tag: tag, skip_preprocess_references: true)
            rule_builder.lhs = new_token
            rule_builder.user_code = token
            rule_builder.complete_input
            rule_builder.setup_rules(parameterizing_rule_resolver)

            @rule_builders_for_derived_rules << rule_builder
          else
            raise "Unexpected token. #{token}"
          end
        end
      end

      def lhs_s_value(token, bindings)
        s_values = token.args.map do |arg|
          resolved = bindings.resolve_symbol(arg)
          if resolved.is_a?(Lexer::Token::InstantiateRule)
            [resolved.s_value, resolved.args.map(&:s_value)]
          else
            resolved.s_value
          end
        end
        "#{token.rule_name}_#{s_values.join('_')}"
      end

      def resolve_inline(parameterizing_rule_resolver)
        rhs.each_with_index do |token, i|
          if inline_rule = parameterizing_rule_resolver.find_inline(token)
            inline_rule.rhs_list.each_with_index do |inline_rhs|
              rule_builder = RuleBuilder.new(@rule_counter, @midrule_action_counter, lhs_tag: lhs_tag, skip_preprocess_references: true)
              resolve_inline_rhs(rule_builder, inline_rhs, i)
              rule_builder.lhs = lhs
              rule_builder.line = line
              rule_builder.user_code = replace_inline_user_code(inline_rhs, i)
              rule_builder.complete_input
              rule_builder.setup_rules(parameterizing_rule_resolver)
              @rule_builders_for_inline_rules << rule_builder
            end
          end
        end
      end

      def resolve_inline_rhs(rule_builder, inline_rhs, index)
        rhs.each_with_index do |token, i|
          if index == i
            inline_rhs.symbols.each { |sym| rule_builder.add_rhs(sym) }
          else
            rule_builder.add_rhs(token)
          end
        end
      end

      def replace_inline_user_code(inline_rhs, index)
        return user_code if inline_rhs.user_code.nil?
        return user_code if user_code.nil?

        code = user_code.s_value.gsub(/\$#{index + 1}/, inline_rhs.user_code.s_value)
        Lrama::Lexer::Token::UserCode.new(s_value: code, location: user_code.location)
      end

      def numberize_references
        # Bison n'th component is 1-origin
        (rhs + [user_code]).compact.each.with_index(1) do |token, i|
          next unless token.is_a?(Lrama::Lexer::Token::UserCode)

          token.references.each do |ref|
            ref_name = ref.name

            if ref_name
              if ref_name == '$'
                ref.name = '$'
              else
                candidates = ([lhs] + rhs).each_with_index.select {|token, _i| token.referred_by?(ref_name) }

                if candidates.size >= 2
                  token.invalid_ref(ref, "Referring symbol `#{ref_name}` is duplicated.")
                end

                unless (referring_symbol = candidates.first)
                  token.invalid_ref(ref, "Referring symbol `#{ref_name}` is not found.")
                end

                if referring_symbol[1] == 0 # Refers to LHS
                  ref.name = '$'
                else
                  ref.number = referring_symbol[1]
                end
              end
            end

            if ref.number
              # TODO: When Inlining is implemented, for example, if `$1` is expanded to multiple RHS tokens,
              #       `$2` needs to access `$2 + n` to actually access it. So, after the Inlining implementation,
              #       it needs resolves from number to index.
              ref.index = ref.number
            end

            # TODO: Need to check index of @ too?
            next if ref.type == :at

            if ref.index
              # TODO: Prohibit $0 even so Bison allows it?
              # See: https://www.gnu.org/software/bison/manual/html_node/Actions.html
              token.invalid_ref(ref, "Can not refer following component. #{ref.index} >= #{i}.") if ref.index >= i
              rhs[ref.index - 1].referred = true
            end
          end
        end
      end

      def flush_user_code
        if (c = @user_code)
          @rhs << c
          @user_code = nil
        end
      end
    end
  end
end
