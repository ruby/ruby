# frozen_string_literal: true

module Lrama
  class Grammar
    class Code
      class RuleAction < Code
        def initialize(type:, token_code:, rule:)
          super(type: type, token_code: token_code)
          @rule = rule
        end

        private

        # * ($$) yyval
        # * (@$) yyloc
        # * ($:$) error
        # * ($1) yyvsp[i]
        # * (@1) yylsp[i]
        # * ($:1) i - 1
        #
        #
        # Consider a rule like
        #
        #   class: keyword_class { $1 } tSTRING { $2 + $3 } keyword_end { $class = $1 + $keyword_end }
        #
        # For the semantic action of original rule:
        #
        # "Rule"                class: keyword_class { $1 } tSTRING { $2 + $3 } keyword_end { $class = $1 + $keyword_end }
        # "Position in grammar"                   $1     $2      $3          $4          $5
        # "Index for yyvsp"                       -4     -3      -2          -1           0
        # "$:n"                                  $:1    $:2     $:3         $:4         $:5
        # "index of $:n"                          -5     -4      -3          -2          -1
        #
        #
        # For the first midrule action:
        #
        # "Rule"                class: keyword_class { $1 } tSTRING { $2 + $3 } keyword_end { $class = $1 + $keyword_end }
        # "Position in grammar"                   $1
        # "Index for yyvsp"                        0
        # "$:n"                                  $:1
        def reference_to_c(ref)
          case
          when ref.type == :dollar && ref.name == "$" # $$
            tag = ref.ex_tag || lhs.tag
            raise_tag_not_found_error(ref) unless tag
            # @type var tag: Lexer::Token::Tag
            "(yyval.#{tag.member})"
          when ref.type == :at && ref.name == "$" # @$
            "(yyloc)"
          when ref.type == :index && ref.name == "$" # $:$
            raise "$:$ is not supported"
          when ref.type == :dollar # $n
            i = -position_in_rhs + ref.index
            tag = ref.ex_tag || rhs[ref.index - 1].tag
            raise_tag_not_found_error(ref) unless tag
            # @type var tag: Lexer::Token::Tag
            "(yyvsp[#{i}].#{tag.member})"
          when ref.type == :at # @n
            i = -position_in_rhs + ref.index
            "(yylsp[#{i}])"
          when ref.type == :index # $:n
            i = -position_in_rhs + ref.index
            "(#{i} - 1)"
          else
            raise "Unexpected. #{self}, #{ref}"
          end
        end

        def position_in_rhs
          # If rule is not derived rule, User Code is only action at
          # the end of rule RHS. In such case, the action is located on
          # `@rule.rhs.count`.
          @rule.position_in_original_rule_rhs || @rule.rhs.count
        end

        # If this is midrule action, RHS is an RHS of the original rule.
        def rhs
          (@rule.original_rule || @rule).rhs
        end

        # Unlike `rhs`, LHS is always an LHS of the rule.
        def lhs
          @rule.lhs
        end

        def raise_tag_not_found_error(ref)
          raise "Tag is not specified for '$#{ref.value}' in '#{@rule.display_name}'"
        end
      end
    end
  end
end
