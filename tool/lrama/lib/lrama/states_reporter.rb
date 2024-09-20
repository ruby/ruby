# frozen_string_literal: true

module Lrama
  class StatesReporter
    include Lrama::Report::Duration

    def initialize(states)
      @states = states
    end

    def report(io, **options)
      report_duration(:report) do
        _report(io, **options)
      end
    end

    private

    def _report(io, grammar: false, rules: false, terms: false, states: false, itemsets: false, lookaheads: false, solved: false, counterexamples: false, verbose: false)
      report_unused_rules(io) if rules
      report_unused_terms(io) if terms
      report_conflicts(io)
      report_grammar(io) if grammar
      report_states(io, itemsets, lookaheads, solved, counterexamples, verbose)
    end

    def report_unused_terms(io)
      look_aheads = @states.states.each do |state|
        state.reduces.flat_map do |reduce|
          reduce.look_ahead unless reduce.look_ahead.nil?
        end
      end

      next_terms = @states.states.flat_map do |state|
        state.shifts.map(&:next_sym).select(&:term?)
      end

      unused_symbols = @states.terms.select do |term|
        !(look_aheads + next_terms).include?(term)
      end

      unless unused_symbols.empty?
        io << "#{unused_symbols.count} Unused Terms\n\n"
        unused_symbols.each_with_index do |term, index|
          io << sprintf("%5d %s\n", index, term.id.s_value)
        end
        io << "\n\n"
      end
    end

    def report_unused_rules(io)
      used_rules = @states.rules.flat_map(&:rhs)

      unused_rules = @states.rules.map(&:lhs).select do |rule|
        !used_rules.include?(rule) && rule.token_id != 0
      end

      unless unused_rules.empty?
        io << "#{unused_rules.count} Unused Rules\n\n"
        unused_rules.each_with_index do |rule, index|
          io << sprintf("%5d %s\n", index, rule.display_name)
        end
        io << "\n\n"
      end
    end

    def report_conflicts(io)
      has_conflict = false

      @states.states.each do |state|
        messages = []
        cs = state.conflicts.group_by(&:type)
        if cs[:shift_reduce]
          messages << "#{cs[:shift_reduce].count} shift/reduce"
        end

        if cs[:reduce_reduce]
          messages << "#{cs[:reduce_reduce].count} reduce/reduce"
        end

        unless messages.empty?
          has_conflict = true
          io << "State #{state.id} conflicts: #{messages.join(', ')}\n"
        end
      end

      if has_conflict
        io << "\n\n"
      end
    end

    def report_grammar(io)
      io << "Grammar\n"
      last_lhs = nil

      @states.rules.each do |rule|
        if rule.empty_rule?
          r = "ε"
        else
          r = rule.rhs.map(&:display_name).join(" ")
        end

        if rule.lhs == last_lhs
          io << sprintf("%5d %s| %s\n", rule.id, " " * rule.lhs.display_name.length, r)
        else
          io << "\n"
          io << sprintf("%5d %s: %s\n", rule.id, rule.lhs.display_name, r)
        end

        last_lhs = rule.lhs
      end
      io << "\n\n"
    end

    def report_states(io, itemsets, lookaheads, solved, counterexamples, verbose)
      if counterexamples
        cex = Counterexamples.new(@states)
      end

      @states.states.each do |state|
        # Report State
        io << "State #{state.id}\n\n"

        # Report item
        last_lhs = nil
        list = itemsets ? state.items : state.kernels
        list.sort_by {|i| [i.rule_id, i.position] }.each do |item|
          if item.empty_rule?
            r = "ε •"
          else
            r = item.rhs.map(&:display_name).insert(item.position, "•").join(" ")
          end
          if item.lhs == last_lhs
            l = " " * item.lhs.id.s_value.length + "|"
          else
            l = item.lhs.id.s_value + ":"
          end
          la = ""
          if lookaheads && item.end_of_rule?
            reduce = state.find_reduce_by_item!(item)
            look_ahead = reduce.selected_look_ahead
            unless look_ahead.empty?
              la = "  [#{look_ahead.map(&:display_name).join(", ")}]"
            end
          end
          last_lhs = item.lhs

          io << sprintf("%5i %s %s%s\n", item.rule_id, l, r, la)
        end
        io << "\n"

        # Report shifts
        tmp = state.term_transitions.reject do |shift, _|
          shift.not_selected
        end.map do |shift, next_state|
          [shift.next_sym, next_state.id]
        end
        max_len = tmp.map(&:first).map(&:display_name).map(&:length).max
        tmp.each do |term, state_id|
          io << "    #{term.display_name.ljust(max_len)}  shift, and go to state #{state_id}\n"
        end
        io << "\n" unless tmp.empty?

        # Report error caused by %nonassoc
        nl = false
        tmp = state.resolved_conflicts.select do |resolved|
          resolved.which == :error
        end.map do |error|
          error.symbol.display_name
        end
        max_len = tmp.map(&:length).max
        tmp.each do |name|
          nl = true
          io << "    #{name.ljust(max_len)}  error (nonassociative)\n"
        end
        io << "\n" unless tmp.empty?

        # Report reduces
        nl = false
        max_len = state.non_default_reduces.flat_map(&:look_ahead).compact.map(&:display_name).map(&:length).max || 0
        max_len = [max_len, "$default".length].max if state.default_reduction_rule
        ary = []

        state.non_default_reduces.each do |reduce|
          reduce.look_ahead.each do |term|
            ary << [term, reduce]
          end
        end

        ary.sort_by do |term, reduce|
          term.number
        end.each do |term, reduce|
          rule = reduce.item.rule
          io << "    #{term.display_name.ljust(max_len)}  reduce using rule #{rule.id} (#{rule.lhs.display_name})\n"
          nl = true
        end

        if (r = state.default_reduction_rule)
          nl = true
          s = "$default".ljust(max_len)

          if r.initial_rule?
            io << "    #{s}  accept\n"
          else
            io << "    #{s}  reduce using rule #{r.id} (#{r.lhs.display_name})\n"
          end
        end
        io << "\n" if nl

        # Report nonterminal transitions
        tmp = []
        max_len = 0
        state.nterm_transitions.each do |shift, next_state|
          nterm = shift.next_sym
          tmp << [nterm, next_state.id]
          max_len = [max_len, nterm.id.s_value.length].max
        end
        tmp.uniq!
        tmp.sort_by! do |nterm, state_id|
          nterm.number
        end
        tmp.each do |nterm, state_id|
          io << "    #{nterm.id.s_value.ljust(max_len)}  go to state #{state_id}\n"
        end
        io << "\n" unless tmp.empty?

        if solved
          # Report conflict resolutions
          state.resolved_conflicts.each do |resolved|
            io << "    #{resolved.report_message}\n"
          end
          io << "\n" unless state.resolved_conflicts.empty?
        end

        if counterexamples && state.has_conflicts?
          # Report counterexamples
          examples = cex.compute(state)
          examples.each do |example|
            label0 = example.type == :shift_reduce ? "shift/reduce" : "reduce/reduce"
            label1 = example.type == :shift_reduce ? "Shift derivation"  : "First Reduce derivation"
            label2 = example.type == :shift_reduce ? "Reduce derivation" : "Second Reduce derivation"

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

        if verbose
          # Report direct_read_sets
          io << "  [Direct Read sets]\n"
          direct_read_sets = @states.direct_read_sets
          @states.nterms.each do |nterm|
            terms = direct_read_sets[[state.id, nterm.token_id]]
            next unless terms
            next if terms.empty?

            str = terms.map {|sym| sym.id.s_value }.join(", ")
            io << "    read #{nterm.id.s_value}  shift #{str}\n"
          end
          io << "\n"

          # Report reads_relation
          io << "  [Reads Relation]\n"
          @states.nterms.each do |nterm|
            a = @states.reads_relation[[state.id, nterm.token_id]]
            next unless a

            a.each do |state_id2, nterm_id2|
              n = @states.nterms.find {|n| n.token_id == nterm_id2 }
              io << "    (State #{state_id2}, #{n.id.s_value})\n"
            end
          end
          io << "\n"

          # Report read_sets
          io << "  [Read sets]\n"
          read_sets = @states.read_sets
          @states.nterms.each do |nterm|
            terms = read_sets[[state.id, nterm.token_id]]
            next unless terms
            next if terms.empty?

            terms.each do |sym|
              io << "    #{sym.id.s_value}\n"
            end
          end
          io << "\n"

          # Report includes_relation
          io << "  [Includes Relation]\n"
          @states.nterms.each do |nterm|
            a = @states.includes_relation[[state.id, nterm.token_id]]
            next unless a

            a.each do |state_id2, nterm_id2|
              n = @states.nterms.find {|n| n.token_id == nterm_id2 }
              io << "    (State #{state.id}, #{nterm.id.s_value}) -> (State #{state_id2}, #{n.id.s_value})\n"
            end
          end
          io << "\n"

          # Report lookback_relation
          io << "  [Lookback Relation]\n"
          @states.rules.each do |rule|
            a = @states.lookback_relation[[state.id, rule.id]]
            next unless a

            a.each do |state_id2, nterm_id2|
              n = @states.nterms.find {|n| n.token_id == nterm_id2 }
              io << "    (Rule: #{rule.display_name}) -> (State #{state_id2}, #{n.id.s_value})\n"
            end
          end
          io << "\n"

          # Report follow_sets
          io << "  [Follow sets]\n"
          follow_sets = @states.follow_sets
          @states.nterms.each do |nterm|
            terms = follow_sets[[state.id, nterm.token_id]]

            next unless terms

            terms.each do |sym|
              io << "    #{nterm.id.s_value} -> #{sym.id.s_value}\n"
            end
          end
          io << "\n"

          # Report LA
          io << "  [Look-Ahead Sets]\n"
          tmp = []
          max_len = 0
          @states.rules.each do |rule|
            syms = @states.la[[state.id, rule.id]]
            next unless syms

            tmp << [rule, syms]
            max_len = ([max_len] + syms.map {|s| s.id.s_value.length }).max
          end
          tmp.each do |rule, syms|
            syms.each do |sym|
              io << "    #{sym.id.s_value.ljust(max_len)}  reduce using rule #{rule.id} (#{rule.lhs.id.s_value})\n"
            end
          end
          io << "\n" unless tmp.empty?
        end

        # End of Report State
        io << "\n"
      end
    end
  end
end
