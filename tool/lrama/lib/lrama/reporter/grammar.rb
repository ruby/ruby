# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Reporter
    class Grammar
      # @rbs (?grammar: bool, **bool _) -> void
      def initialize(grammar: false, **_)
        @grammar = grammar
      end

      # @rbs (IO io, Lrama::States states) -> void
      def report(io, states)
        return unless @grammar

        io << "Grammar\n"
        last_lhs = nil

        states.rules.each do |rule|
          if rule.empty_rule?
            r = "ε"
          else
            r = rule.rhs.map(&:display_name).join(" ")
          end

          if rule.lhs == last_lhs
            io << sprintf("%5d %s| %s", rule.id, " " * rule.lhs.display_name.length, r) << "\n"
          else
            io << "\n"
            io << sprintf("%5d %s: %s", rule.id, rule.lhs.display_name, r) << "\n"
          end

          last_lhs = rule.lhs
        end
        io << "\n\n"
      end
    end
  end
end
