# frozen_string_literal: true
module RubyVM::MJIT
  def self.runtime_stats
    stats = {}

    # Insn exits
    INSNS.each_value do |insn|
      exits = C.mjit_insn_exits[insn.bin]
      if exits > 0
        stats[:"exit_#{insn.name}"] = exits
      end
    end

    # Runtime stats
    C.rb_mjit_runtime_counters.members.each do |member|
      stats[member] = C.rb_mjit_counters.public_send(member)
    end

    # Other stats are calculated here
    stats[:side_exit_count] = stats.select { |name, _count| name.start_with?('exit_') }.sum(&:last)
    if stats[:vm_insns_count] > 0
      retired_in_mjit = stats[:mjit_insns_count] - stats[:side_exit_count]
      stats[:total_insns_count] = retired_in_mjit + stats[:vm_insns_count]
      stats[:ratio_in_mjit] = 100.0 * retired_in_mjit / stats[:total_insns_count]
    end

    stats
  end

  class << self
    private

    def print_stats
      stats = runtime_stats
      $stderr.puts("***MJIT: Printing MJIT statistics on exit***")

      print_counters(stats, prefix: 'send_', prompt: 'method call exit reasons')

      $stderr.puts "side_exit_count:       #{format('%10d', stats[:side_exit_count])}"
      $stderr.puts "total_insns_count:     #{format('%10d', stats[:total_insns_count])}" if stats.key?(:total_insns_count)
      $stderr.puts "vm_insns_count:        #{format('%10d', stats[:vm_insns_count])}" if stats.key?(:vm_insns_count)
      $stderr.puts "mjit_insns_count:      #{format('%10d', stats[:mjit_insns_count])}"
      $stderr.puts "ratio_in_mjit:         #{format('%9.1f', stats[:ratio_in_mjit])}%" if stats.key?(:ratio_in_mjit)

      print_exit_counts(stats)
    end

    def print_counters(stats, prefix:, prompt:)
      $stderr.puts("#{prompt}: ")
      counters = stats.filter { |key, _| key.start_with?(prefix) }
      counters.filter! { |_, value| value != 0 }
      counters.transform_keys! { |key| key.to_s.delete_prefix(prefix) }

      if counters.empty?
        $stderr.puts("    (all relevant counters are zero)")
        return
      end

      counters = counters.to_a
      counters.sort_by! { |(_, counter_value)| counter_value }
      longest_name_length = counters.max_by { |(name, _)| name.length }.first.length
      total = counters.sum { |(_, counter_value)| counter_value }

      counters.reverse_each do |(name, value)|
        percentage = value.fdiv(total) * 100
        $stderr.printf("    %*s %10d (%4.1f%%)\n", longest_name_length, name, value, percentage)
      end
    end

    def print_exit_counts(stats, how_many: 20, padding: 2)
      exits = stats.filter_map { |name, count| [name.to_s.delete_prefix('exit_'), count] if name.start_with?('exit_') }.to_h
      return if exits.empty?

      top_exits = exits.sort_by { |_name, count| -count }.first(how_many).to_h
      total_exits = exits.values.sum
      $stderr.puts "Top-#{top_exits.size} most frequent exit ops (#{format("%.1f", 100.0 * top_exits.values.sum / total_exits)}% of exits):"

      name_width  = top_exits.map { |name, _count| name.length }.max + padding
      count_width = top_exits.map { |_name, count| count.to_s.length }.max + padding
      top_exits.each do |name, count|
        ratio = 100.0 * count / total_exits
        $stderr.puts "#{format("%#{name_width}s", name)}: #{format("%#{count_width}d", count)} (#{format('%.1f', ratio)}%)"
      end
    end
  end
end
