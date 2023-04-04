# frozen_string_literal: true

# This module allows for introspection of YJIT, CRuby's in-process
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

  # Check if --yjit-stats is used.
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

  # Resume YJIT compilation after paused on startup with --yjit-pause
  def self.resume
    Primitive.rb_yjit_resume
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

    # Loop through the instructions and set the frame hash with the data.
    # We use nonexistent.def for the file name, otherwise insns.def will be displayed
    # and that information isn't useful in this context.
    RubyVM::INSTRUCTION_NAMES.each_with_index do |name, frame_id|
      frame_hash = { samples: 0, total_samples: 0, edges: {}, name: name, file: "nonexistent.def", line: nil, lines: {} }
      results[:frames][frame_id] = frame_hash
      frames[frame_id] = frame_hash
    end

    # Loop through the raw_samples and build the hashes for StackProf.
    # The loop is based off an example in the StackProf documentation and therefore
    # this functionality can only work with that library.
    #
    # Raw Samples:
    # [ length, frame1, frame2, frameN, ..., instruction, count
    #
    # Line Samples
    # [ length, line_1, line_2, line_n, ..., dummy value, count
    i = 0
    while i < raw_samples.length
      stack_length = raw_samples[i] + 1
      i += 1 # consume the stack length

      prev_frame_id = nil
      stack_length.times do |idx|
        idx += i
        frame_id = raw_samples[idx]

        if prev_frame_id
          prev_frame = frames[prev_frame_id]
          prev_frame[:edges][frame_id] ||= 0
          prev_frame[:edges][frame_id] += 1
        end

        frame_info = frames[frame_id]
        frame_info[:total_samples] += 1

        frame_info[:lines][line_samples[idx]] ||= [0, 0]
        frame_info[:lines][line_samples[idx]][0] += 1

        prev_frame_id = frame_id
      end

      i += stack_length # consume the stack

      top_frame_id = prev_frame_id
      top_frame_line = 1

      sample_count = raw_samples[i]

      frames[top_frame_id][:samples] += sample_count
      frames[top_frame_id][:lines] ||= {}
      frames[top_frame_id][:lines][top_frame_line] ||= [0, 0]
      frames[top_frame_id][:lines][top_frame_line][1] += sample_count

      samples_count += sample_count
      i += 1
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
  # If `--yjit-exit-locations` is passed, a file named
  # "yjit_exit_locations.dump" will automatically be generated.
  #
  # If you want to collect traces manually, call `dump_exit_locations`
  # directly.
  #
  # Note that calling this in a script will generate stats after the
  # dump is created, so the stats data may include exits from the
  # dump itself.
  #
  # In a script call:
  #
  #   at_exit do
  #     RubyVM::YJIT.dump_exit_locations("my_file.dump")
  #   end
  #
  # Then run the file with the following options:
  #
  #   ruby --yjit --yjit-trace-exits test.rb
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
  def self.runtime_stats(context: false)
    stats = Primitive.rb_yjit_get_stats(context)
    return stats if stats.nil?

    stats[:object_shape_count] = Primitive.object_shape_count
    return stats unless Primitive.rb_yjit_stats_enabled_p

    side_exits = total_exit_count(stats)
    total_exits = side_exits + stats[:leave_interp_return]

    # Number of instructions that finish executing in YJIT.
    # See :count-placement: about the subtraction.
    retired_in_yjit = stats[:exec_instruction] - side_exits

    # Average length of instruction sequences executed by YJIT
    avg_len_in_yjit = retired_in_yjit.to_f / total_exits

    # This only available on yjit stats builds
    if stats.key?(:vm_insns_count)
      # Proportion of instructions that retire in YJIT
      total_insns_count = retired_in_yjit + stats[:vm_insns_count]
      yjit_ratio_pct = 100.0 * retired_in_yjit.to_f / total_insns_count
      stats[:total_insns_count] = total_insns_count
      stats[:ratio_in_yjit] = yjit_ratio_pct
    end

    # Make those stats available in RubyVM::YJIT.runtime_stats as well
    stats[:side_exit_count]  = side_exits
    stats[:total_exit_count] = total_exits
    stats[:avg_len_in_yjit]  = avg_len_in_yjit

    stats
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
    return nil unless self.enabled?

    # If a method or proc is passed in, get its iseq
    iseq = RubyVM::InstructionSequence.of(iseq)
    Primitive.rb_yjit_insns_compiled(iseq)
  end

  # Free and recompile all existing JIT code
  def self.code_gc
    Primitive.rb_yjit_code_gc
  end

  def self.simulate_oom! # :nodoc:
    Primitive.rb_yjit_simulate_oom_bang
  end

  # Avoid calling a method here to not interfere with compilation tests
  if Primitive.rb_yjit_stats_enabled_p
    at_exit do
      _print_stats
      _dump_locations
    end
  end

  class << self
    private

    def _dump_locations # :nodoc:
      return unless trace_exit_locations_enabled?

      filename = "yjit_exit_locations.dump"
      dump_exit_locations(filename)

      $stderr.puts("YJIT exit locations dumped to `#{filename}`.")
    end

    # Format and print out counters
    def _print_stats # :nodoc:
      stats = runtime_stats(context: true)
      return unless stats

      $stderr.puts("***YJIT: Printing YJIT statistics on exit***")

      print_counters(stats, prefix: 'send_', prompt: 'method call exit reasons: ')
      print_counters(stats, prefix: 'invokeblock_', prompt: 'invokeblock exit reasons: ')
      print_counters(stats, prefix: 'invokesuper_', prompt: 'invokesuper exit reasons: ')
      print_counters(stats, prefix: 'leave_', prompt: 'leave exit reasons: ')
      print_counters(stats, prefix: 'gbpp_', prompt: 'getblockparamproxy exit reasons: ')
      print_counters(stats, prefix: 'getivar_', prompt: 'getinstancevariable exit reasons:')
      print_counters(stats, prefix: 'setivar_', prompt: 'setinstancevariable exit reasons:')
      print_counters(stats, prefix: 'oaref_', prompt: 'opt_aref exit reasons: ')
      print_counters(stats, prefix: 'expandarray_', prompt: 'expandarray exit reasons: ')
      print_counters(stats, prefix: 'opt_getinlinecache_', prompt: 'opt_getinlinecache exit reasons: ')
      print_counters(stats, prefix: 'invalidate_', prompt: 'invalidation reasons: ')

      # Number of failed compiler invocations
      compilation_failure = stats[:compilation_failure]

      $stderr.puts "num_send:              " + format_number(13, stats[:num_send])
      $stderr.puts "num_send_known_class:  " + format_number_pct(13, stats[:num_send_known_class], stats[:num_send])
      $stderr.puts "num_send_polymorphic:  " + format_number_pct(13, stats[:num_send_polymorphic], stats[:num_send])
      if stats[:num_send_x86_rel32] != 0 || stats[:num_send_x86_reg] != 0
        $stderr.puts "num_send_x86_rel32:    " + format_number(13,  stats[:num_send_x86_rel32])
        $stderr.puts "num_send_x86_reg:      " + format_number(13, stats[:num_send_x86_reg])
      end

      $stderr.puts "iseq_stack_too_large:  " + format_number(13, stats[:iseq_stack_too_large])
      $stderr.puts "iseq_too_long:         " + format_number(13, stats[:iseq_too_long])
      $stderr.puts "temp_reg_opnd:         " + format_number(13, stats[:temp_reg_opnd])
      $stderr.puts "temp_mem_opnd:         " + format_number(13, stats[:temp_mem_opnd])
      $stderr.puts "temp_spill:            " + format_number(13, stats[:temp_spill])
      $stderr.puts "bindings_allocations:  " + format_number(13, stats[:binding_allocations])
      $stderr.puts "bindings_set:          " + format_number(13, stats[:binding_set])
      $stderr.puts "compilation_failure:   " + format_number(13, compilation_failure) if compilation_failure != 0
      $stderr.puts "compiled_iseq_count:   " + format_number(13, stats[:compiled_iseq_count])
      $stderr.puts "compiled_block_count:  " + format_number(13, stats[:compiled_block_count])
      $stderr.puts "compiled_branch_count: " + format_number(13, stats[:compiled_branch_count])
      $stderr.puts "block_next_count:      " + format_number(13, stats[:block_next_count])
      $stderr.puts "defer_count:           " + format_number(13, stats[:defer_count])
      $stderr.puts "defer_empty_count:     " + format_number(13, stats[:defer_empty_count])

      $stderr.puts "branch_insn_count:     " + format_number(13, stats[:branch_insn_count])
      $stderr.puts "branch_known_count:    " + format_number_pct(13, stats[:branch_known_count], stats[:branch_insn_count])

      $stderr.puts "freed_iseq_count:      " + format_number(13, stats[:freed_iseq_count])
      $stderr.puts "invalidation_count:    " + format_number(13, stats[:invalidation_count])
      $stderr.puts "constant_state_bumps:  " + format_number(13, stats[:constant_state_bumps])
      $stderr.puts "get_ivar_max_depth:    " + format_number(13, stats[:get_ivar_max_depth])
      $stderr.puts "inline_code_size:      " + format_number(13, stats[:inline_code_size])
      $stderr.puts "outlined_code_size:    " + format_number(13, stats[:outlined_code_size])
      $stderr.puts "freed_code_size:       " + format_number(13, stats[:freed_code_size])
      $stderr.puts "code_region_size:      " + format_number(13, stats[:code_region_size])
      $stderr.puts "yjit_alloc_size:       " + format_number(13, stats[:yjit_alloc_size]) if stats.key?(:yjit_alloc_size)
      $stderr.puts "live_context_size:     " + format_number(13, stats[:live_context_size])
      $stderr.puts "live_context_count:    " + format_number(13, stats[:live_context_count])
      $stderr.puts "live_page_count:       " + format_number(13, stats[:live_page_count])
      $stderr.puts "freed_page_count:      " + format_number(13, stats[:freed_page_count])
      $stderr.puts "code_gc_count:         " + format_number(13, stats[:code_gc_count])
      $stderr.puts "num_gc_obj_refs:       " + format_number(13, stats[:num_gc_obj_refs])
      $stderr.puts "object_shape_count:    " + format_number(13, stats[:object_shape_count])
      $stderr.puts "side_exit_count:       " + format_number(13, stats[:side_exit_count])
      $stderr.puts "total_exit_count:      " + format_number(13, stats[:total_exit_count])
      $stderr.puts "total_insns_count:     " + format_number(13, stats[:total_insns_count]) if stats.key?(:total_insns_count)
      if stats.key?(:vm_insns_count)
        $stderr.puts "vm_insns_count:        " + format_number(13, stats[:vm_insns_count])
      end
      $stderr.puts "yjit_insns_count:      " + format_number(13, stats[:exec_instruction])
      if stats.key?(:ratio_in_yjit)
        $stderr.puts "ratio_in_yjit:         " + ("%12.1f" % stats[:ratio_in_yjit]) + "%"
      end
      $stderr.puts "avg_len_in_yjit:       " + ("%13.1f" % stats[:avg_len_in_yjit])

      print_sorted_exit_counts(stats, prefix: "exit_")
    end

    def print_sorted_exit_counts(stats, prefix:, how_many: 20, left_pad: 4) # :nodoc:
      total_exits = total_exit_count(stats)

      if total_exits > 0
        exits = []
        stats.each do |k, v|
          if k.start_with?(prefix)
            exits.push [k.to_s.delete_prefix(prefix), v]
          end
        end

        exits = exits.select { |_name, count| count > 0 }.max_by(how_many) { |_name, count| count }

        top_n_total = exits.sum { |name, count| count }
        top_n_exit_pct = 100.0 * top_n_total / total_exits

        $stderr.puts "Top-#{exits.size} most frequent exit ops (#{"%.1f" % top_n_exit_pct}% of exits):"

        longest_insn_name_len = exits.max_by { |name, count| name.length }.first.length
        exits.each do |name, count|
          padding = longest_insn_name_len + left_pad
          padded_name = "%#{padding}s" % name
          padded_count = format_number_pct(10, count, total_exits)
          $stderr.puts("#{padded_name}: #{padded_count}")
        end
      else
        $stderr.puts "total_exits:           " + format_number(10, total_exits)
      end
    end

    def total_exit_count(stats, prefix: "exit_") # :nodoc:
      total = 0
      stats.each do |k,v|
        total += v if k.start_with?(prefix)
      end
      total
    end

    def print_counters(counters, prefix:, prompt:) # :nodoc:
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
        padded_name = name.rjust(longest_name_length, ' ')
        padded_count = format_number_pct(10, value, total)
        $stderr.puts("    #{padded_name}: #{padded_count}")
      end
    end

    # Format large numbers with comma separators for readability
    def format_number(pad, number)
      integer, decimal = number.to_s.split(".")
      d_groups = integer.chars.to_a.reverse.each_slice(3)
      with_commas = d_groups.map(&:join).join(',').reverse
      formatted = [with_commas, decimal].compact.join(".")
      formatted.rjust(pad, ' ')
    end

    # Format a number along with a percentage over a total value
    def format_number_pct(pad, number, total)
      padded_count = format_number(pad, number)
      percentage = number.fdiv(total) * 100
      formatted_pct = "%4.1f%%" % percentage
      "#{padded_count} (#{formatted_pct})"
    end
  end
end
