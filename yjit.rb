# frozen_string_literal: true
# :markup: markdown

# This module allows for introspection of \YJIT, CRuby's just-in-time compiler.
# Everything in the module is highly implementation specific and the API might
# be less stable compared to the standard library.
#
# This module may not exist if \YJIT does not support the particular platform
# for which CRuby is built.
module RubyVM::YJIT
  # Check if \YJIT is enabled.
  def self.enabled?
    Primitive.cexpr! 'RBOOL(rb_yjit_enabled_p)'
  end

  # Check if `--yjit-stats` is used.
  def self.stats_enabled?
    Primitive.rb_yjit_stats_enabled_p
  end

  # Check if rb_yjit_trace_exit_locations_enabled_p is enabled.
  def self.trace_exit_locations_enabled? # :nodoc:
    Primitive.rb_yjit_trace_exit_locations_enabled_p
  end

  # Discard statistics collected for `--yjit-stats`.
  def self.reset_stats!
    Primitive.rb_yjit_reset_stats_bang
  end

  # Enable \YJIT compilation. `stats` option decides whether to enable \YJIT stats or not.
  #
  # * `false`: Disable stats.
  # * `true`: Enable stats. Print stats at exit.
  # * `:quiet`: Enable stats. Do not print stats at exit.
  def self.enable(stats: false)
    return false if enabled?
    at_exit { print_and_dump_stats } if stats
    Primitive.rb_yjit_enable(stats, stats != :quiet)
  end

  # If --yjit-trace-exits is enabled parse the hashes from
  # Primitive.rb_yjit_get_exit_locations into a format readable
  # by Stackprof. This will allow us to find the exact location of a
  # side exit in YJIT based on the instruction that is exiting.
  def self.exit_locations # :nodoc:
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
      stack_length = raw_samples[i]
      i += 1 # consume the stack length

      sample_count = raw_samples[i + stack_length]

      prev_frame_id = nil
      stack_length.times do |idx|
        idx += i
        frame_id = raw_samples[idx]

        if prev_frame_id
          prev_frame = frames[prev_frame_id]
          prev_frame[:edges][frame_id] ||= 0
          prev_frame[:edges][frame_id] += sample_count
        end

        frame_info = frames[frame_id]
        frame_info[:total_samples] += sample_count

        frame_info[:lines][line_samples[idx]] ||= [0, 0]
        frame_info[:lines][line_samples[idx]][0] += sample_count

        prev_frame_id = frame_id
      end

      i += stack_length # consume the stack

      top_frame_id = prev_frame_id
      top_frame_line = 1

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
  #     at_exit do
  #       RubyVM::YJIT.dump_exit_locations("my_file.dump")
  #     end
  #
  # Then run the file with the following options:
  #
  #     ruby --yjit --yjit-trace-exits test.rb
  #
  # Once the code is done running, use Stackprof to read the dump file.
  # See Stackprof documentation for options.
  def self.dump_exit_locations(filename)
    unless trace_exit_locations_enabled?
      raise ArgumentError, "--yjit-trace-exits must be enabled to use dump_exit_locations."
    end

    File.binwrite(filename, Marshal.dump(RubyVM::YJIT.exit_locations))
  end

  # Return a hash for statistics generated for the `--yjit-stats` command line option.
  # Return `nil` when option is not passed or unavailable.
  def self.runtime_stats(context: false)
    stats = Primitive.rb_yjit_get_stats(context)
    return stats if stats.nil?

    stats[:object_shape_count] = Primitive.object_shape_count
    return stats unless Primitive.rb_yjit_stats_enabled_p

    side_exits = total_exit_count(stats)
    total_exits = side_exits + stats[:leave_interp_return]

    # Number of instructions that finish executing in YJIT.
    # See :count-placement: about the subtraction.
    retired_in_yjit = stats[:yjit_insns_count] - side_exits

    # Average length of instruction sequences executed by YJIT
    avg_len_in_yjit = total_exits > 0 ? retired_in_yjit.to_f / total_exits : 0

    # Proportion of instructions that retire in YJIT
    total_insns_count = retired_in_yjit + stats[:vm_insns_count]
    yjit_ratio_pct = 100.0 * retired_in_yjit.to_f / total_insns_count
    stats[:total_insns_count] = total_insns_count
    stats[:ratio_in_yjit] = yjit_ratio_pct

    # Make those stats available in RubyVM::YJIT.runtime_stats as well
    stats[:side_exit_count]  = side_exits
    stats[:total_exit_count] = total_exits
    stats[:avg_len_in_yjit]  = avg_len_in_yjit

    stats
  end

  # Format and print out counters as a String. This returns a non-empty
  # content only when `--yjit-stats` is enabled.
  def self.stats_string
    # Lazily require StringIO to avoid breaking miniruby
    require 'stringio'
    strio = StringIO.new
    _print_stats(out: strio)
    strio.string
  end

  # Produce disassembly for an iseq. This requires a `--enable-yjit=dev` build.
  def self.disasm(iseq) # :nodoc:
    # If a method or proc is passed in, get its iseq
    iseq = RubyVM::InstructionSequence.of(iseq)

    if !self.enabled?
      warn(
        "YJIT needs to be enabled to produce disasm output, e.g.\n" +
        "ruby --yjit-call-threshold=1 my_script.rb (see doc/yjit/yjit.md)"
      )
      return nil
    end

    disasm_str = Primitive.rb_yjit_disasm_iseq(iseq)

    if !disasm_str
      warn(
        "YJIT disasm is only available when YJIT is built in dev mode, i.e.\n" +
        "./configure --enable-yjit=dev (see doc/yjit/yjit.md)\n"
      )
      return nil
    end

    # Produce the disassembly string
    # Include the YARV iseq disasm in the string for additional context
    iseq.disasm + "\n" + disasm_str
  end

  # Produce a list of instructions compiled by YJIT for an iseq
  def self.insns_compiled(iseq) # :nodoc:
    return nil unless self.enabled?

    # If a method or proc is passed in, get its iseq
    iseq = RubyVM::InstructionSequence.of(iseq)
    Primitive.rb_yjit_insns_compiled(iseq)
  end

  # Discard existing compiled code to reclaim memory
  # and allow for recompilations in the future.
  def self.code_gc
    Primitive.rb_yjit_code_gc
  end

  def self.simulate_oom! # :nodoc:
    Primitive.rb_yjit_simulate_oom_bang
  end

  # Avoid calling a Ruby method here to not interfere with compilation tests
  if Primitive.rb_yjit_stats_enabled_p
    at_exit { print_and_dump_stats }
  end

  class << self
    # :stopdoc:
    private

    # Print stats and dump exit locations
    def print_and_dump_stats # :nodoc:
      if Primitive.rb_yjit_print_stats_p
        _print_stats
      end
      _dump_locations
    end

    def _dump_locations # :nodoc:
      return unless trace_exit_locations_enabled?

      filename = "yjit_exit_locations.dump"
      dump_exit_locations(filename)

      $stderr.puts("YJIT exit locations dumped to `#{filename}`.")
    end

    # Print a summary of reasons for adverse performance events (e.g. exits)
    def _print_stats_reasons(stats, out) # :nodoc:
      print_counters(stats, out: out, prefix: 'send_', prompt: 'method call fallback reasons: ')
      print_counters(stats, out: out, prefix: 'invokeblock_', prompt: 'invokeblock fallback reasons: ')
      print_counters(stats, out: out, prefix: 'invokesuper_', prompt: 'invokesuper fallback reasons: ')
      print_counters(stats, out: out, prefix: 'guard_send_', prompt: 'method call exit reasons: ')
      print_counters(stats, out: out, prefix: 'guard_invokeblock_', prompt: 'invokeblock exit reasons: ')
      print_counters(stats, out: out, prefix: 'guard_invokesuper_', prompt: 'invokesuper exit reasons: ')
      print_counters(stats, out: out, prefix: 'gbpp_', prompt: 'getblockparamproxy exit reasons: ')
      print_counters(stats, out: out, prefix: 'getivar_', prompt: 'getinstancevariable exit reasons:')
      print_counters(stats, out: out, prefix: 'setivar_', prompt: 'setinstancevariable exit reasons:')
      %w[
        branchif
        branchnil
        branchunless
        definedivar
        expandarray
        invokebuiltin
        jump
        leave
        objtostring
        opt_aref
        opt_aref_with
        opt_aset
        opt_case_dispatch
        opt_div
        opt_getconstant_path
        opt_minus
        opt_mod
        opt_mult
        opt_plus
        opt_succ
        setlocal
        splatkw
      ].each do |insn|
        print_counters(stats, out: out, prefix: "#{insn}_", prompt: "#{insn} exit reasons:", optional: true)
      end
      print_counters(stats, out: out, prefix: 'lshift_', prompt: 'left shift (opt_ltlt) exit reasons: ')
      print_counters(stats, out: out, prefix: 'rshift_', prompt: 'right shift (>>) exit reasons: ')
      print_counters(stats, out: out, prefix: 'invalidate_', prompt: 'invalidation reasons: ')
    end

    # Format and print out counters
    def _print_stats(out: $stderr) # :nodoc:
      stats = runtime_stats(context: true)
      return unless Primitive.rb_yjit_stats_enabled_p

      out.puts("***YJIT: Printing YJIT statistics on exit***")

      _print_stats_reasons(stats, out)

      # Number of failed compiler invocations
      compilation_failure = stats[:compilation_failure]

      code_region_overhead = stats[:code_region_size] - (stats[:inline_code_size] + stats[:outlined_code_size])

      out.puts "num_send:              " + format_number(13, stats[:num_send])
      out.puts "num_send_known_class:  " + format_number_pct(13, stats[:num_send_known_class], stats[:num_send])
      out.puts "num_send_polymorphic:  " + format_number_pct(13, stats[:num_send_polymorphic], stats[:num_send])
      out.puts "num_send_megamorphic:  " + format_number_pct(13, stats[:send_megamorphic], stats[:num_send])
      out.puts "num_send_dynamic:      " + format_number_pct(13, stats[:num_send_dynamic], stats[:num_send])
      out.puts "num_send_cfunc:        " + format_number_pct(13, stats[:num_send_cfunc], stats[:num_send])
      out.puts "num_send_cfunc_inline: " + format_number_pct(13, stats[:num_send_cfunc_inline], stats[:num_send_cfunc])
      out.puts "num_send_iseq:         " + format_number_pct(13, stats[:num_send_iseq], stats[:num_send])
      out.puts "num_send_iseq_leaf:    " + format_number_pct(13, stats[:num_send_iseq_leaf], stats[:num_send_iseq])
      out.puts "num_send_iseq_inline:  " + format_number_pct(13, stats[:num_send_iseq_inline], stats[:num_send_iseq])
      if stats[:num_send_x86_rel32] != 0 || stats[:num_send_x86_reg] != 0
        out.puts "num_send_x86_rel32:    " + format_number(13,  stats[:num_send_x86_rel32])
        out.puts "num_send_x86_reg:      " + format_number(13, stats[:num_send_x86_reg])
      end
      out.puts "num_getivar_megamorphic: " + format_number(11, stats[:num_getivar_megamorphic])
      out.puts "num_setivar_megamorphic: " + format_number(11, stats[:num_setivar_megamorphic])
      out.puts "num_opt_case_megamorphic: " + format_number(10, stats[:num_opt_case_dispatch_megamorphic])
      out.puts "num_throw:             " + format_number(13, stats[:num_throw])
      out.puts "num_throw_break:       " + format_number_pct(13, stats[:num_throw_break], stats[:num_throw])
      out.puts "num_throw_retry:       " + format_number_pct(13, stats[:num_throw_retry], stats[:num_throw])
      out.puts "num_throw_return:      " + format_number_pct(13, stats[:num_throw_return], stats[:num_throw])
      out.puts "num_lazy_frame_check:  " + format_number(13, stats[:num_lazy_frame_check])
      out.puts "num_lazy_frame_push:   " + format_number_pct(13, stats[:num_lazy_frame_push], stats[:num_lazy_frame_check])
      out.puts "lazy_frame_count:      " + format_number(13, stats[:lazy_frame_count])
      out.puts "lazy_frame_failure:    " + format_number(13, stats[:lazy_frame_failure])

      out.puts "iseq_stack_too_large:  " + format_number(13, stats[:iseq_stack_too_large])
      out.puts "iseq_too_long:         " + format_number(13, stats[:iseq_too_long])
      out.puts "temp_reg_opnd:         " + format_number(13, stats[:temp_reg_opnd])
      out.puts "temp_mem_opnd:         " + format_number(13, stats[:temp_mem_opnd])
      out.puts "temp_spill:            " + format_number(13, stats[:temp_spill])
      out.puts "bindings_allocations:  " + format_number(13, stats[:binding_allocations])
      out.puts "bindings_set:          " + format_number(13, stats[:binding_set])
      out.puts "compilation_failure:   " + format_number(13, compilation_failure) if compilation_failure != 0
      out.puts "live_iseq_count:       " + format_number(13, stats[:live_iseq_count])
      out.puts "iseq_alloc_count:      " + format_number(13, stats[:iseq_alloc_count])
      out.puts "compiled_iseq_entry:   " + format_number(13, stats[:compiled_iseq_entry])
      out.puts "cold_iseq_entry:       " + format_number_pct(13, stats[:cold_iseq_entry], stats[:compiled_iseq_entry] + stats[:cold_iseq_entry])
      out.puts "compiled_iseq_count:   " + format_number(13, stats[:compiled_iseq_count])
      out.puts "compiled_blockid_count:" + format_number(13, stats[:compiled_blockid_count])
      out.puts "compiled_block_count:  " + format_number(13, stats[:compiled_block_count])
      if stats[:compiled_blockid_count] != 0
        out.puts "versions_per_block:    " + format_number(13, "%4.3f" % (stats[:compiled_block_count].fdiv(stats[:compiled_blockid_count])))
      end
      out.puts "max_inline_versions:   " + format_number(13, stats[:max_inline_versions])
      out.puts "compiled_branch_count: " + format_number(13, stats[:compiled_branch_count])
      out.puts "compile_time_ms:       " + format_number(13, stats[:compile_time_ns] / (1000 * 1000))
      out.puts "block_next_count:      " + format_number(13, stats[:block_next_count])
      out.puts "defer_count:           " + format_number(13, stats[:defer_count])
      out.puts "defer_empty_count:     " + format_number(13, stats[:defer_empty_count])

      out.puts "branch_insn_count:     " + format_number(13, stats[:branch_insn_count])
      out.puts "branch_known_count:    " + format_number_pct(13, stats[:branch_known_count], stats[:branch_insn_count])

      out.puts "freed_iseq_count:      " + format_number(13, stats[:freed_iseq_count])
      out.puts "invalidation_count:    " + format_number(13, stats[:invalidation_count])
      out.puts "inline_code_size:      " + format_number(13, stats[:inline_code_size])
      out.puts "outlined_code_size:    " + format_number(13, stats[:outlined_code_size])
      out.puts "code_region_size:      " + format_number(13, stats[:code_region_size])
      out.puts "code_region_overhead:  " + format_number_pct(13, code_region_overhead, stats[:code_region_size])

      out.puts "freed_code_size:       " + format_number(13, stats[:freed_code_size])
      out.puts "yjit_alloc_size:       " + format_number(13, stats[:yjit_alloc_size]) if stats.key?(:yjit_alloc_size)
      out.puts "live_context_size:     " + format_number(13, stats[:live_context_size])
      out.puts "live_context_count:    " + format_number(13, stats[:live_context_count])
      out.puts "live_page_count:       " + format_number(13, stats[:live_page_count])
      out.puts "freed_page_count:      " + format_number(13, stats[:freed_page_count])
      out.puts "code_gc_count:         " + format_number(13, stats[:code_gc_count])
      out.puts "num_gc_obj_refs:       " + format_number(13, stats[:num_gc_obj_refs])
      out.puts "object_shape_count:    " + format_number(13, stats[:object_shape_count])
      out.puts "side_exit_count:       " + format_number(13, stats[:side_exit_count])
      out.puts "total_exit_count:      " + format_number(13, stats[:total_exit_count])
      out.puts "total_insns_count:     " + format_number(13, stats[:total_insns_count])
      out.puts "vm_insns_count:        " + format_number(13, stats[:vm_insns_count])
      out.puts "yjit_insns_count:      " + format_number(13, stats[:yjit_insns_count])
      out.puts "ratio_in_yjit:         " + ("%12.1f" % stats[:ratio_in_yjit]) + "%"
      out.puts "avg_len_in_yjit:       " + ("%13.1f" % stats[:avg_len_in_yjit])

      print_sorted_exit_counts(stats, out: out, prefix: "exit_")

      print_sorted_method_calls(stats[:cfunc_calls], stats[:num_send_cfunc], out: out, type: 'C')
      print_sorted_method_calls(stats[:iseq_calls], stats[:num_send_iseq], out: out, type: 'ISEQ')
    end

    def print_sorted_method_calls(calls, num_calls, out:, type:, how_many: 20, left_pad: 4) # :nodoc:
      return if calls.empty?

      # Sort calls by decreasing frequency and keep the top N
      pairs = calls.map { |k,v| [k, v] }
      pairs.sort_by! {|pair| -pair[1] }
      pairs = pairs[0...how_many]

      top_n_total = pairs.sum { |name, count| count }
      top_n_pct = 100.0 * top_n_total / num_calls

      out.puts "Top-#{pairs.size} most frequent #{type} calls (#{"%.1f" % top_n_pct}% of #{type} calls):"

      count_width = format_number(0, pairs[0][1]).length
      pairs.each do |name, count|
        padded_count = format_number_pct(count_width, count, num_calls)
        out.puts("  #{padded_count}: #{name}")
      end
    end

    def print_sorted_exit_counts(stats, out:, prefix:, how_many: 20, left_pad: 4) # :nodoc:
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

        out.puts "Top-#{exits.size} most frequent exit ops (#{"%.1f" % top_n_exit_pct}% of exits):"

        count_width = format_number(0, exits[0][1]).length
        exits.each do |name, count|
          padded_count = format_number_pct(count_width, count, total_exits)
          out.puts("  #{padded_count}: #{name}")
        end
      else
        out.puts "total_exits:           " + format_number(10, total_exits)
      end
    end

    def total_exit_count(stats, prefix: "exit_") # :nodoc:
      total = 0
      stats.each do |k,v|
        total += v if k.start_with?(prefix)
      end
      total
    end

    def print_counters(counters, out:, prefix:, prompt:, optional: false) # :nodoc:
      counters = counters.filter { |key, _| key.start_with?(prefix) }
      counters.filter! { |_, value| value != 0 }
      counters.transform_keys! { |key| key.to_s.delete_prefix(prefix) }

      if counters.empty?
        unless optional
          out.puts(prompt)
          out.puts("    (all relevant counters are zero)")
        end
        return
      else
        out.puts(prompt)
      end

      counters = counters.to_a
      counters.sort_by! { |(_, counter_value)| counter_value }
      longest_name_length = counters.max_by { |(name, _)| name.length }.first.length
      total = counters.sum { |(_, counter_value)| counter_value }

      counters.reverse_each do |(name, value)|
        padded_name = name.rjust(longest_name_length, ' ')
        padded_count = format_number_pct(10, value, total)
        out.puts("    #{padded_name}: #{padded_count}")
      end
    end

    # Format large numbers with comma separators for readability
    def format_number(pad, number) # :nodoc:
      s = number.to_s
      i = s.index('.') || s.size
      s.insert(i -= 3, ',') while i > 3
      s.rjust(pad, ' ')
    end

    # Format a number along with a percentage over a total value
    def format_number_pct(pad, number, total) # :nodoc:
      padded_count = format_number(pad, number)
      percentage = number.fdiv(total) * 100
      formatted_pct = "%4.1f%%" % percentage
      "#{padded_count} (#{formatted_pct})"
    end

    # :startdoc:
  end
end
