# frozen_string_literal: true

# This module allows for introspection of ZJIT, CRuby's just-in-time compiler.
# Everything in the module is highly implementation specific and the API might
# be less stable compared to the standard library.
#
# This module may not exist if ZJIT does not support the particular platform
# for which CRuby is built.
module RubyVM::ZJIT
  # Blocks that are called when YJIT is enabled
  @jit_hooks = []
  # Avoid calling a Ruby method here to avoid interfering with compilation tests
  if Primitive.rb_zjit_get_stats_file_path_p
    at_exit { print_stats_file }
  end
  if Primitive.rb_zjit_print_stats_p
    at_exit { print_stats }
  end
  if Primitive.rb_zjit_trace_exit_locations_enabled_p
    at_exit { dump_locations }
  end
end

class << RubyVM::ZJIT
  # Check if ZJIT is enabled
  def enabled?
    Primitive.cexpr! 'RBOOL(rb_zjit_enabled_p)'
  end

  # Enable ZJIT compilation.
  def enable
    return false if enabled?

    if Primitive.cexpr! 'RBOOL(rb_yjit_enabled_p)'
      warn("Only one JIT can be enabled at the same time.")
      return false
    end

    Primitive.rb_zjit_enable
  end

  # Check if `--zjit-trace-exits` is used
  def trace_exit_locations_enabled?
    Primitive.rb_zjit_trace_exit_locations_enabled_p
  end

  # If --zjit-trace-exits is enabled parse the hashes from
  # Primitive.rb_zjit_get_exit_locations into a format readable
  # by Stackprof. This will allow us to find the exact location of a
  # side exit in ZJIT based on the instruction that is exiting.
  def exit_locations
    return unless trace_exit_locations_enabled?

    results = Primitive.rb_zjit_get_exit_locations
    raw_samples = results[:raw]
    line_samples = results[:lines]
    frames = results[:frames]
    samples_count = 0

    # Use nonexistent.def as a dummy file name.
    frame_template = { samples: 0, total_samples: 0, edges: {}, name: name, file: "nonexistent.def", line: nil, lines: {} }

    # Loop through all possible instructions and setup the frame hash.
    RubyVM::INSTRUCTION_NAMES.each_with_index do |name, frame_id|
      frames[frame_id] = frame_template.dup.tap { |h| h[:name] = name }
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

    # These values are mandatory to include for stackprof, but we don't use them.
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
  #   RubyVM::ZJIT.dump_exit_locations("my_file.dump")
  #
  # Then run the file with the following options:
  #
  #   ruby --zjit --zjit-stats --zjit-trace-exits test.rb
  #
  # Once the code is done running, use Stackprof to read the dump file.
  # See Stackprof documentation for options.
  def dump_exit_locations(filename)
    unless trace_exit_locations_enabled?
      raise ArgumentError, "--zjit-trace-exits must be enabled to use dump_exit_locations."
    end

    File.open(filename, "wb") do |file|
      Marshal.dump(RubyVM::ZJIT.exit_locations, file)
      file.size
    end
  end

  # Check if `--zjit-stats` is used
  def stats_enabled?
    Primitive.rb_zjit_stats_enabled_p
  end

  # Return ZJIT statistics as a Hash
  def stats(target_key = nil)
    Primitive.rb_zjit_stats(target_key)
  end

  # Discard statistics collected for `--zjit-stats`.
  def reset_stats!
    Primitive.rb_zjit_reset_stats_bang
  end

  # Get the summary of ZJIT statistics as a String
  def stats_string
    buf = +"***ZJIT: Printing ZJIT statistics on exit***\n"
    stats = self.stats

    if stats[:guard_type_count].nonzero?
      stats[:guard_type_exit_ratio] = stats[:exit_guard_type_failure].to_f / stats[:guard_type_count] * 100
    end
    if stats[:guard_shape_count].nonzero?
      stats[:guard_shape_exit_ratio] = stats[:exit_guard_shape_failure].to_f / stats[:guard_shape_count] * 100
    end

    # Show counters independent from exit_* or dynamic_send_*
    print_counters_with_prefix(prefix: 'not_inlined_cfuncs_', prompt: 'not inlined C methods', buf:, stats:, limit: 20)
    print_counters_with_prefix(prefix: 'ccall_', prompt: 'calls to C functions from JIT code', buf:, stats:, limit: 20)
    # Don't show not_annotated_cfuncs right now because it mostly duplicates not_inlined_cfuncs
    # print_counters_with_prefix(prefix: 'not_annotated_cfuncs_', prompt: 'not annotated C methods', buf:, stats:, limit: 20)

    # Show fallback counters, ordered by the typical amount of fallbacks for the prefix at the time
    print_counters_with_prefix(prefix: 'unspecialized_send_def_type_', prompt: 'not optimized method types for send', buf:, stats:, limit: 20)
    print_counters_with_prefix(prefix: 'unspecialized_send_without_block_def_type_', prompt: 'not optimized method types for send_without_block', buf:, stats:, limit: 20)
    print_counters_with_prefix(prefix: 'uncategorized_fallback_yarv_insn_', prompt: 'instructions with uncategorized fallback reason', buf:, stats:, limit: 20)
    print_counters_with_prefix(prefix: 'send_fallback_', prompt: 'send fallback reasons', buf:, stats:, limit: 20)
    print_counters_with_prefix(prefix: 'setivar_fallback_', prompt: 'setivar fallback reasons', buf:, stats:, limit: 5)
    print_counters_with_prefix(prefix: 'getivar_fallback_', prompt: 'getivar fallback reasons', buf:, stats:, limit: 5)
    print_counters_with_prefix(prefix: 'definedivar_fallback_', prompt: 'definedivar fallback reasons', buf:, stats:, limit: 5)
    print_counters_with_prefix(prefix: 'invokeblock_handler_', prompt: 'invokeblock handler', buf:, stats:, limit: 10)

    # Show most popular unsupported call features. Because each call can
    # use multiple complex features, a decrease in this number does not
    # necessarily mean an increase in number of optimized calls.
    print_counters_with_prefix(prefix: 'complex_arg_pass_', prompt: 'popular complex argument-parameter features not optimized', buf:, stats:, limit: 10)

    # Show exit counters, ordered by the typical amount of exits for the prefix at the time
    print_counters_with_prefix(prefix: 'compile_error_', prompt: 'compile error reasons', buf:, stats:, limit: 20)
    print_counters_with_prefix(prefix: 'unhandled_yarv_insn_', prompt: 'unhandled YARV insns', buf:, stats:, limit: 20)
    print_counters_with_prefix(prefix: 'unhandled_hir_insn_', prompt: 'unhandled HIR insns', buf:, stats:, limit: 20)
    print_counters_with_prefix(prefix: 'exit_', prompt: 'side exit reasons', buf:, stats:, limit: 20)

    # Show no-prefix counters, having the most important stat `ratio_in_zjit` at the end
    print_counters([
      :send_count,
      :dynamic_send_count,
      :optimized_send_count,
      :dynamic_setivar_count,
      :dynamic_getivar_count,
      :dynamic_definedivar_count,
      :iseq_optimized_send_count,
      :inline_cfunc_optimized_send_count,
      :inline_iseq_optimized_send_count,
      :non_variadic_cfunc_optimized_send_count,
      :variadic_cfunc_optimized_send_count,
    ], buf:, stats:, right_align: true, base: :send_count)
    print_counters([
      :compiled_iseq_count,
      :failed_iseq_count,

      :compile_time_ns,
      :profile_time_ns,
      :gc_time_ns,
      :invalidation_time_ns,

      :vm_write_pc_count,
      :vm_write_sp_count,
      :vm_write_locals_count,
      :vm_write_stack_count,
      :vm_write_to_parent_iseq_local_count,
      :vm_read_from_parent_iseq_local_count,

      :guard_type_count,
      :guard_type_exit_ratio,
      :guard_shape_count,
      :guard_shape_exit_ratio,

      :code_region_bytes,
      :zjit_alloc_bytes,
      :total_mem_bytes,

      :side_exit_count,
      :total_insn_count,
      :vm_insn_count,
      :zjit_insn_count,
      :ratio_in_zjit,
    ], buf:, stats:)

    buf
  end

  # Assert that any future ZJIT compilation will return a function pointer
  def assert_compiles # :nodoc:
    Primitive.rb_zjit_assert_compiles
  end

  # :stopdoc:
  private

  # Register a block to be called when ZJIT is enabled
  def add_jit_hook(hook)
    @jit_hooks << hook
  end

  # Run ZJIT hooks registered by `#with_jit`
  def call_jit_hooks
    @jit_hooks.each(&:call)
    @jit_hooks.clear
  end

  def print_counters(keys, buf:, stats:, right_align: false, base: nil)
    key_pad = keys.map { |key| key.to_s.sub(/_time_ns\z/, '_time').size }.max + 1
    key_align = '-' unless right_align
    value_pad = keys.filter_map { |key| stats[key] }.map { |value| number_with_delimiter(value).size }.max

    keys.each do |key|
      # Some stats like vm_insn_count and ratio_in_zjit are not supported on the release build
      next unless stats.key?(key)
      value = stats[key]
      if base && key != base
        total = stats[base]
        if total.nonzero?
          ratio = " (%4.1f%%)" % (100.0 * value / total)
        end
      end

      case key
      when :ratio_in_zjit
        value = '%0.1f%%' % value
      when :guard_type_exit_ratio, :guard_shape_exit_ratio
        value = '%0.1f%%' % value
      when /_time_ns\z/
        key = key.to_s.sub(/_time_ns\z/, '_time')
        value = "#{number_with_delimiter(value / 10**6)}ms"
      else
        value = number_with_delimiter(value)
      end

      buf << "%#{key_align}*s %*s%s\n" % [key_pad, "#{key}:", value_pad, value, ratio]
    end
  end

  def print_counters_with_prefix(buf:, stats:, prefix:, prompt:, limit: nil)
    counters = stats.select { |key, value| key.start_with?(prefix) && value > 0 }
    return if counters.empty?

    counters.transform_keys! { |key| key.to_s.delete_prefix(prefix) }
    key_pad = counters.keys.map(&:size).max
    value_pad = counters.values.map { |value| number_with_delimiter(value).size }.max
    total = counters.values.sum

    counters = counters.to_a
    counters.sort_by! { |_, value| -value }
    counters = counters.first(limit) if limit

    buf << "Top-#{counters.size} " if limit
    buf << "#{prompt}"
    buf << " (%.1f%% of total #{number_with_delimiter(total)})" % (100.0 * counters.map(&:last).sum / total) if limit
    buf << ":\n"
    counters.each do |key, value|
      buf << "  %*s: %*s (%4.1f%%)\n" % [key_pad, key, value_pad, number_with_delimiter(value), (100.0 * value / total)]
    end
  end

  def number_with_delimiter(number)
    s = number.to_s
    i = s.index('.') || s.size
    s.insert(i -= 3, ',') while i > 3
    s
  end

  # Print ZJIT stats
  def print_stats
    $stderr.write stats_string
  end

  # Print ZJIT stats to file
  def print_stats_file
    filename = Primitive.rb_zjit_get_stats_file_path_p
    File.open(filename, "wb") do |file|
      file.write stats_string
    end
  end

  def dump_locations # :nodoc:
    return unless trace_exit_locations_enabled?

    filename = "zjit_exits_#{Process.pid}.dump"
    n_bytes = dump_exit_locations(filename)

    absolute_filename = File.expand_path(filename)
    $stderr.puts("#{n_bytes} bytes written to #{absolute_filename}")
  end
end
