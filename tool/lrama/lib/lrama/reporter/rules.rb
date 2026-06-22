# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Reporter
    class Rules
      # @rbs (?rules: bool, **bool _) -> void
      def initialize(rules: false, **_)
        @rules = rules
      end

      # @rbs (IO io, Lrama::States states) -> void
      def report(io, states)
        return unless @rules

        used_rules = states.rules.flat_map(&:rhs)

        unless used_rules.empty?
          io << "Rule Usage Frequency\n\n"
          frequency_counts = used_rules.each_with_object(Hash.new(0)) { |rule, counts| counts[rule] += 1 }

          frequency_counts
            .select { |rule,| !rule.midrule? }
            .sort_by { |rule, count| [-count, rule.name] }
            .each_with_index { |(rule, count), i| io << sprintf("%5d %s (%d times)", i, rule.name, count) << "\n" }
          io << "\n\n"
        end

        unused_rules = states.rules.map(&:lhs).select do |rule|
          !used_rules.include?(rule) && rule.token_id != 0
        end

        unless unused_rules.empty?
          io << "#{unused_rules.count} Unused Rules\n\n"
          unused_rules.each_with_index do |rule, index|
            io << sprintf("%5d %s", index, rule.display_name) << "\n"
          end
          io << "\n\n"
        end
      end
    end
  end
end
