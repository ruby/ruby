# frozen_string_literal: true

# This module allows for introspection of YJIT, CRuby's experimental in-process
# just-in-time compiler. This module exists only to help develop YJIT, as such,
# everything in the module is highly implementation specific and comes with no
# API stability guarantee whatsoever.
#
# This module may not exist if YJIT does not support the particular platform
# for which CRuby is built. There is also no API stability guarantee as to in
# what situations this module is defined.
module RubyVM::YJIT
  # Check if YJIT is enabled
  def self.enabled?
    Primitive.cexpr! 'RBOOL(rb_yjit_enabled_p())'
  end

  def self.stats_enabled?
    Primitive.rb_yjit_stats_enabled_p
  end

  # Check if rb_yjit_trace_exit_locations_enabled_p is enabled.
  def self.trace_exit_locations_enabled?
    Primitive.rb_yjit_trace_exit_locations_enabled_p
  end

  # Discard statistics collected for --yjit-stats.
  def self.reset_stats!
    Primitive.rb_yjit_reset_stats_bang
  end

  # If --yjit-trace-exits is enabled parse the hashes from
  # Primitive.rb_yjit_get_exit_locations into a format readable
  # by Stackprof. This will allow us to find the exact location of a
  # side exit in YJIT based on the instruction that is exiting.
  def self.exit_locations
    return unless trace_exit_locations_enabled?

    results = Primitive.rb_yjit_get_exit_locations
    raw_samples = results[:raw].dup
    line_samples = results[:lines].dup
    frames = results[:frames].dup
    samples_count = 0

    frames.each do |frame_id, frame|
      frame[:samples] = 0
      frame[:edges] = {}
    end

    # Loop through the instructions and set the frame hash with the data.
    # We use nonexistent.def for the file name, otherwise insns.def will be displayed
    # and that information isn't useful in this context.
    RubyVM::INSTRUCTION_NAMES.each_with_index do |name, frame_id|
      frame_hash = { samples: 0, total_samples: 0, edges: {}, name: name, file: "nonexistent.def", line: nil }
      results[:frames][frame_id] = frame_hash
      frames[frame_id] = frame_hash
    end

    # Loop through the raw_samples and build the hashes for StackProf.
    # The loop is based off an example in the StackProf documentation and therefore
    # this functionality can only work with that library.
    while raw_samples.length > 0
      stack_trace = raw_samples.shift(raw_samples.shift + 1)
      lines = line_samples.shift(line_samples.shift + 1)
      prev_frame_id = nil

      stack_trace.each_with_index do |frame_id, idx|
        if prev_frame_id
          prev_frame = frames[prev_frame_id]
          prev_frame[:edges][frame_id] ||= 0
          prev_frame[:edges][frame_id] += 1
        end

        frame_info = frames[frame_id]
        frame_info[:total_samples] ||= 0
        frame_info[:total_samples] += 1

        frame_info[:lines] ||= {}
        frame_info[:lines][lines[idx]] ||= [0, 0]
        frame_info[:lines][lines[idx]][0] += 1

        prev_frame_id = frame_id
      end

      top_frame_id = stack_trace.last
      top_frame_line = 1

      frames[top_frame_id][:samples] += 1
      frames[top_frame_id][:lines] ||= {}
      frames[top_frame_id][:lines][top_frame_line] ||= [0, 0]
      frames[top_frame_id][:lines][top_frame_line][1] += 1

      samples_count += raw_samples.shift
      line_samples.shift
    end

    results[:samples] = samples_count
    # Set missed_samples and gc_samples to 0 as their values
    # don't matter to us in this context.
    results[:missed_samples] = 0
    results[:gc_samples] = 0
    results
  end

  # Marshal dumps exit locations to the given filename.
  #
  # Usage:
  #
  # In a script call:
  #
  #   RubyVM::YJIT.dump_exit_locations("my_file.dump")
  #
  # Then run the file with the following options:
  #
  #   ruby --yjit --yjit-stats --yjit-trace-exits test.rb
  #
  # Once the code is done running, use Stackprof to read the dump file.
  # See Stackprof documentation for options.
  def self.dump_exit_locations(filename)
    unless trace_exit_locations_enabled?
      raise ArgumentError, "--yjit-trace-exits must be enabled to use dump_exit_locations."
    end

    File.binwrite(filename, Marshal.dump(RubyVM::YJIT.exit_locations))
  end

  # Return a hash for statistics generated for the --yjit-stats command line option.
  # Return nil when option is not passed or unavailable.
  def self.runtime_stats
    Primitive.rb_yjit_get_stats
  end

  # Produce disassembly for an iseq
  def self.disasm(iseq)
    # If a method or proc is passed in, get its iseq
    iseq = RubyVM::InstructionSequence.of(iseq)

    if self.enabled?
      # Produce the disassembly string
      # Include the YARV iseq disasm in the string for additional context
      iseq.disasm + "\n" + Primitive.rb_yjit_disasm_iseq(iseq)
    else
      iseq.disasm
    end
  end

  # Produce a list of instructions compiled by YJIT for an iseq
  def self.insns_compiled(iseq)
    # If a method or proc is passed in, get its iseq
    iseq = RubyVM::InstructionSequence.of(iseq)

    if self.enabled?
      Primitive.rb_yjit_insns_compiled(iseq)
    else
      Qnil
    end
  end

  def self.simulate_oom!
    Primitive.rb_yjit_simulate_oom_bang
  end

  # Avoid calling a method here to not interfere with compilation tests
  if Primitive.rb_yjit_stats_enabled_p
    at_exit { _print_stats }
  end

  class << self
    private

    # Format and print out counters
    def _print_stats
      stats = runtime_stats
      return unless stats

      $stderr.puts("***YJIT: Printing YJIT statistics on exit***")

      print_counters(stats, prefix: 'send_', prompt: 'method call exit reasons: ')
      print_counters(stats, prefix: 'invokesuper_', prompt: 'invokesuper exit reasons: ')
      print_counters(stats, prefix: 'leave_', prompt: 'leave exit reasons: ')
      print_counters(stats, prefix: 'gbpp_', prompt: 'getblockparamproxy exit reasons: ')
      print_counters(stats, prefix: 'getivar_', prompt: 'getinstancevariable exit reasons:')
      print_counters(stats, prefix: 'setivar_', prompt: 'setinstancevariable exit reasons:')
      print_counters(stats, prefix: 'oaref_', prompt: 'opt_aref exit reasons: ')
      print_counters(stats, prefix: 'expandarray_', prompt: 'expandarray exit reasons: ')
      print_counters(stats, prefix: 'opt_getinlinecache_', prompt: 'opt_getinlinecache exit reasons: ')
      print_counters(stats, prefix: 'invalidate_', prompt: 'invalidation reasons: ')

      side_exits = total_exit_count(stats)
      total_exits = side_exits + stats[:leave_interp_return]

      # Number of instructions that finish executing in YJIT.
      # See :count-placement: about the subtraction.
      retired_in_yjit = stats[:exec_instruction] - side_exits

      # Average length of instruction sequences executed by YJIT
      avg_len_in_yjit = retired_in_yjit.to_f / total_exits

      # Proportion of instructions that retire in YJIT
      total_insns_count = retired_in_yjit + stats[:vm_insns_count]
      yjit_ratio_pct = 100.0 * retired_in_yjit.to_f / total_insns_count

      # Number of failed compiler invocations
      compilation_failure = stats[:compilation_failure]

      $stderr.puts "bindings_allocations:  " + ("%10d" % stats[:binding_allocations])
      $stderr.puts "bindings_set:          " + ("%10d" % stats[:binding_set])
      $stderr.puts "compilation_failure:   " + ("%10d" % compilation_failure) if compilation_failure != 0
      $stderr.puts "compiled_iseq_count:   " + ("%10d" % stats[:compiled_iseq_count])
      $stderr.puts "compiled_block_count:  " + ("%10d" % stats[:compiled_block_count])
      $stderr.puts "invalidation_count:    " + ("%10d" % stats[:invalidation_count])
      $stderr.puts "constant_state_bumps:  " + ("%10d" % stats[:constant_state_bumps])
      $stderr.puts "inline_code_size:      " + ("%10d" % stats[:inline_code_size])
      $stderr.puts "outlined_code_size:    " + ("%10d" % stats[:outlined_code_size])

      $stderr.puts "total_exit_count:      " + ("%10d" % total_exits)
      $stderr.puts "total_insns_count:     " + ("%10d" % total_insns_count)
      $stderr.puts "vm_insns_count:        " + ("%10d" % stats[:vm_insns_count])
      $stderr.puts "yjit_insns_count:      " + ("%10d" % stats[:exec_instruction])
      $stderr.puts "ratio_in_yjit:         " + ("%9.1f" % yjit_ratio_pct) + "%"
      $stderr.puts "avg_len_in_yjit:       " + ("%10.1f" % avg_len_in_yjit)

      print_sorted_exit_counts(stats, prefix: "exit_")
    end

    def print_sorted_exit_counts(stats, prefix:, how_many: 20, left_pad: 4)
      exits = []
      stats.each do |k, v|
        if k.start_with?(prefix)
          exits.push [k.to_s.delete_prefix(prefix), v]
        end
      end

      exits = exits.sort_by { |name, count| -count }[0...how_many]
      total_exits = total_exit_count(stats)

      top_n_total = exits.map { |name, count| count }.sum
      top_n_exit_pct = 100.0 * top_n_total / total_exits

      $stderr.puts "Top-#{how_many} most frequent exit ops (#{"%.1f" % top_n_exit_pct}% of exits):"

      longest_insn_name_len = exits.map { |name, count| name.length }.max
      exits.each do |name, count|
        padding = longest_insn_name_len + left_pad
        padded_name = "%#{padding}s" % name
        padded_count = "%10d" % count
        percent = 100.0 * count / total_exits
        formatted_percent = "%.1f" % percent
        $stderr.puts("#{padded_name}: #{padded_count} (#{formatted_percent}%)" )
      end
    end

    def total_exit_count(stats, prefix: "exit_")
      total = 0
      stats.each do |k,v|
        total += v if k.start_with?(prefix)
      end
      total
    end

    def print_counters(counters, prefix:, prompt:)
      $stderr.puts(prompt)
      counters = counters.filter { |key, _| key.start_with?(prefix) }
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
        $stderr.printf("    %*s %10d (%4.1f%%)\n", longest_name_length, name, value, percentage);
      end
    end
  end
end
