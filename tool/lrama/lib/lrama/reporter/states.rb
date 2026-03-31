# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Reporter
    class States
      # @rbs (?itemsets: bool, ?lookaheads: bool, ?solved: bool, ?counterexamples: bool, ?verbose: bool, **bool _) -> void
      def initialize(itemsets: false, lookaheads: false, solved: false, counterexamples: false, verbose: false, **_)
        @itemsets = itemsets
        @lookaheads = lookaheads
        @solved = solved
        @counterexamples = counterexamples
        @verbose = verbose
      end

      # @rbs (IO io, Lrama::States states, ielr: bool) -> void
      def report(io, states, ielr: false)
        cex = Counterexamples.new(states) if @counterexamples

        states.compute_la_sources_for_conflicted_states
        report_split_states(io, states.states) if ielr

        states.states.each do |state|
          report_state_header(io, state)
          report_items(io, state)
          report_conflicts(io, state)
          report_shifts(io, state)
          report_nonassoc_errors(io, state)
          report_reduces(io, state)
          report_nterm_transitions(io, state)
          report_conflict_resolutions(io, state) if @solved
          report_counterexamples(io, state, cex) if @counterexamples && state.has_conflicts? # @type var cex: Lrama::Counterexamples
          report_verbose_info(io, state, states) if @verbose
          # End of Report State
          io << "\n"
        end
      end

      private

      # @rbs (IO io, Array[Lrama::State] states) -> void
      def report_split_states(io, states)
        ss = states.select(&:split_state?)

        return if ss.empty?

        io << "Split States\n\n"

        ss.each do |state|
          io << "    State #{state.id} is split from state #{state.lalr_isocore.id}\n"
        end

        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_state_header(io, state)
        io << "State #{state.id}\n\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_items(io, state)
        last_lhs = nil
        list = @itemsets ? state.items : state.kernels

        list.sort_by {|i| [i.rule_id, i.position] }.each do |item|
          r = item.empty_rule? ? "ε •" : item.rhs.map(&:display_name).insert(item.position, "•").join(" ")

          l = if item.lhs == last_lhs
            " " * item.lhs.id.s_value.length + "|"
          else
            item.lhs.id.s_value + ":"
          end

          la = ""
          if @lookaheads && item.end_of_rule?
            reduce = state.find_reduce_by_item!(item)
            look_ahead = reduce.selected_look_ahead
            unless look_ahead.empty?
              la = "  [#{look_ahead.compact.map(&:display_name).join(", ")}]"
            end
          end

          last_lhs = item.lhs
          io << sprintf("%5i %s %s%s", item.rule_id, l, r, la) << "\n"
        end

        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_conflicts(io, state)
        return if state.conflicts.empty?

        state.conflicts.each do |conflict|
          syms = conflict.symbols.map { |sym| sym.display_name }
          io << "    Conflict on #{syms.join(", ")}. "

          case conflict.type
          when :shift_reduce
            # @type var conflict: Lrama::State::ShiftReduceConflict
            io << "shift/reduce(#{conflict.reduce.item.rule.lhs.display_name})\n"

            conflict.symbols.each do |token|
              conflict.reduce.look_ahead_sources[token].each do |goto| # steep:ignore NoMethod
                io << "      #{token.display_name} comes from state #{goto.from_state.id} goto by #{goto.next_sym.display_name}\n"
              end
            end
          when :reduce_reduce
            # @type var conflict: Lrama::State::ReduceReduceConflict
            io << "reduce(#{conflict.reduce1.item.rule.lhs.display_name})/reduce(#{conflict.reduce2.item.rule.lhs.display_name})\n"

            conflict.symbols.each do |token|
              conflict.reduce1.look_ahead_sources[token].each do |goto| # steep:ignore NoMethod
                io << "      #{token.display_name} comes from state #{goto.from_state.id} goto by #{goto.next_sym.display_name}\n"
              end

              conflict.reduce2.look_ahead_sources[token].each do |goto| # steep:ignore NoMethod
                io << "      #{token.display_name} comes from state #{goto.from_state.id} goto by #{goto.next_sym.display_name}\n"
              end
            end
          else
            raise "Unknown conflict type #{conflict.type}"
          end

          io << "\n"
        end

        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_shifts(io, state)
        shifts = state.term_transitions.reject(&:not_selected)

        return if shifts.empty?

        next_syms = shifts.map(&:next_sym)
        max_len = next_syms.map(&:display_name).map(&:length).max
        shifts.each do |shift|
          io << "    #{shift.next_sym.display_name.ljust(max_len)}  shift, and go to state #{shift.to_state.id}\n"
        end

        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_nonassoc_errors(io, state)
        error_symbols = state.resolved_conflicts.select { |resolved| resolved.which == :error }.map { |error| error.symbol.display_name }

        return if error_symbols.empty?

        max_len = error_symbols.map(&:length).max
        error_symbols.each do |name|
          io << "    #{name.ljust(max_len)}  error (nonassociative)\n"
        end

        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_reduces(io, state)
        reduce_pairs = [] #: Array[[Lrama::Grammar::Symbol, Lrama::State::Action::Reduce]]

        state.non_default_reduces.each do |reduce|
          reduce.look_ahead&.each do |term|
            reduce_pairs << [term, reduce]
          end
        end

        return if reduce_pairs.empty? && !state.default_reduction_rule

        max_len = [
          reduce_pairs.map(&:first).map(&:display_name).map(&:length).max || 0,
          state.default_reduction_rule ? "$default".length : 0
        ].max

        reduce_pairs.sort_by { |term, _| term.number }.each do |term, reduce|
          rule = reduce.item.rule
          io << "    #{term.display_name.ljust(max_len)}  reduce using rule #{rule.id} (#{rule.lhs.display_name})\n"
        end

        if (r = state.default_reduction_rule)
          s = "$default".ljust(max_len)

          if r.initial_rule?
            io << "    #{s}  accept\n"
          else
            io << "    #{s}  reduce using rule #{r.id} (#{r.lhs.display_name})\n"
          end
        end

        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_nterm_transitions(io, state)
        return if state.nterm_transitions.empty?

        goto_transitions = state.nterm_transitions.sort_by do |goto|
          goto.next_sym.number
        end

        max_len = goto_transitions.map(&:next_sym).map do |nterm|
          nterm.id.s_value.length
        end.max
        goto_transitions.each do |goto|
          io << "    #{goto.next_sym.id.s_value.ljust(max_len)}  go to state #{goto.to_state.id}\n"
        end

        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_conflict_resolutions(io, state)
        return if state.resolved_conflicts.empty?

        state.resolved_conflicts.each do |resolved|
          io << "    #{resolved.report_message}\n"
        end

        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::Counterexamples cex) -> void
      def report_counterexamples(io, state, cex)
        examples = cex.compute(state)

        examples.each do |example|
          is_shift_reduce = example.type == :shift_reduce
          label0 = is_shift_reduce ? "shift/reduce" : "reduce/reduce"
          label1 = is_shift_reduce ? "Shift derivation" : "First Reduce derivation"
          label2 = is_shift_reduce ? "Reduce derivation" : "Second Reduce derivation"

          io << "    #{label0} conflict on token #{example.conflict_symbol.id.s_value}:\n"
          io << "        #{example.path1_item}\n"
          io << "        #{example.path2_item}\n"
          io << "      #{label1}\n"

          example.derivations1.render_strings_for_report.each do |str|
            io << "        #{str}\n"
          end

          io << "      #{label2}\n"

          example.derivations2.render_strings_for_report.each do |str|
            io << "        #{str}\n"
          end
        end
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_verbose_info(io, state, states)
        report_direct_read_sets(io, state, states)
        report_reads_relation(io, state, states)
        report_read_sets(io, state, states)
        report_includes_relation(io, state, states)
        report_lookback_relation(io, state, states)
        report_follow_sets(io, state, states)
        report_look_ahead_sets(io, state, states)
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_direct_read_sets(io, state, states)
        io << "  [Direct Read sets]\n"
        direct_read_sets = states.direct_read_sets

        state.nterm_transitions.each do |goto|
          terms = direct_read_sets[goto]
          next unless terms && !terms.empty?

          str = terms.map { |sym| sym.id.s_value }.join(", ")
          io << "    read #{goto.next_sym.id.s_value}  shift #{str}\n"
        end

        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_reads_relation(io, state, states)
        io << "  [Reads Relation]\n"

        state.nterm_transitions.each do |goto|
          goto2 = states.reads_relation[goto]
          next unless goto2

          goto2.each do |goto2|
            io << "    (State #{goto2.from_state.id}, #{goto2.next_sym.id.s_value})\n"
          end
        end

        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_read_sets(io, state, states)
        io << "  [Read sets]\n"
        read_sets = states.read_sets

        state.nterm_transitions.each do |goto|
          terms = read_sets[goto]
          next unless terms && !terms.empty?

          terms.each do |sym|
            io << "    #{sym.id.s_value}\n"
          end
        end

        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_includes_relation(io, state, states)
        io << "  [Includes Relation]\n"

        state.nterm_transitions.each do |goto|
          gotos = states.includes_relation[goto]
          next unless gotos

          gotos.each do |goto2|
            io << "    (State #{state.id}, #{goto.next_sym.id.s_value}) -> (State #{goto2.from_state.id}, #{goto2.next_sym.id.s_value})\n"
          end
        end

        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_lookback_relation(io, state, states)
        io << "  [Lookback Relation]\n"

        states.rules.each do |rule|
          gotos = states.lookback_relation.dig(state.id, rule.id)
          next unless gotos

          gotos.each do |goto2|
            io << "    (Rule: #{rule.display_name}) -> (State #{goto2.from_state.id}, #{goto2.next_sym.id.s_value})\n"
          end
        end

        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_follow_sets(io, state, states)
        io << "  [Follow sets]\n"
        follow_sets = states.follow_sets

        state.nterm_transitions.each do |goto|
          terms = follow_sets[goto]
          next unless terms

          terms.each do |sym|
            io << "    #{goto.next_sym.id.s_value} -> #{sym.id.s_value}\n"
          end
        end

        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_look_ahead_sets(io, state, states)
        io << "  [Look-Ahead Sets]\n"
        look_ahead_rules = [] #: Array[[Lrama::Grammar::Rule, Array[Lrama::Grammar::Symbol]]]

        states.rules.each do |rule|
          syms = states.la.dig(state.id, rule.id)
          next unless syms

          look_ahead_rules << [rule, syms]
        end

        return if look_ahead_rules.empty?

        max_len = look_ahead_rules.flat_map { |_, syms| syms.map { |s| s.id.s_value.length } }.max

        look_ahead_rules.each do |rule, syms|
          syms.each do |sym|
            io << "    #{sym.id.s_value.ljust(max_len)}  reduce using rule #{rule.id} (#{rule.lhs.id.s_value})\n"
          end
        end

        io << "\n"
      end
    end
  end
end
