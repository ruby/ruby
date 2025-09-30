# frozen_string_literal: true

# This module allows for introspection of ZJIT, CRuby's just-in-time compiler.
# Everything in the module is highly implementation specific and the API might
# be less stable compared to the standard library.
#
# This module may not exist if ZJIT does not support the particular platform
# for which CRuby is built.
module RubyVM::ZJIT
  # Avoid calling a Ruby method here to avoid interfering with compilation tests
  if Primitive.rb_zjit_print_stats_p
    at_exit {
      print_stats
      dump_locations
    }
  end
end

class << RubyVM::ZJIT
  # Check if ZJIT is enabled
  def enabled?
    Primitive.cexpr! 'RBOOL(rb_zjit_enabled_p)'
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

    File.binwrite(filename, Marshal.dump(RubyVM::ZJIT.exit_locations))
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

    # Show counters independent from exit_* or dynamic_send_*
    print_counters_with_prefix(prefix: 'not_optimized_cfuncs_', prompt: 'unoptimized sends to C functions', buf:, stats:, limit: 20)

    # Show fallback counters, ordered by the typical amount of fallbacks for the prefix at the time
    print_counters_with_prefix(prefix: 'unspecialized_def_type_', prompt: 'not optimized method types', buf:, stats:, limit: 20)
    print_counters_with_prefix(prefix: 'not_optimized_yarv_insn_', prompt: 'not optimized instructions', buf:, stats:, limit: 20)
    print_counters_with_prefix(prefix: 'send_fallback_', prompt: 'send fallback reasons', buf:, stats:, limit: 20)

    # Show exit counters, ordered by the typical amount of exits for the prefix at the time
    print_counters_with_prefix(prefix: 'unhandled_yarv_insn_', prompt: 'unhandled YARV insns', buf:, stats:, limit: 20)
    print_counters_with_prefix(prefix: 'compile_error_', prompt: 'compile error reasons', buf:, stats:, limit: 20)
    print_counters_with_prefix(prefix: 'exit_', prompt: 'side exit reasons', buf:, stats:, limit: 20)

    # Show the most important stats ratio_in_zjit at the end
    print_counters([
      :dynamic_send_count,
      :dynamic_getivar_count,
      :dynamic_setivar_count,

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

      :code_region_bytes,
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

  def print_counters(keys, buf:, stats:)
    left_pad = keys.map { |key| key.to_s.sub(/_time_ns\z/, '_time').size }.max + 1
    keys.each do |key|
      # Some stats like vm_insn_count and ratio_in_zjit are not supported on the release build
      next unless stats.key?(key)
      value = stats[key]

      case key
      when :ratio_in_zjit
        value = '%0.1f%%' % value
      when /_time_ns\z/
        key = key.to_s.sub(/_time_ns\z/, '_time')
        value = "#{number_with_delimiter(value / 10**6)}ms"
      else
        value = number_with_delimiter(value)
      end

      buf << "#{"%-#{left_pad}s" % "#{key}:"} #{value}\n"
    end
  end

  def print_counters_with_prefix(buf:, stats:, prefix:, prompt:, limit: nil)
    counters = stats.select { |key, value| key.start_with?(prefix) && value > 0 }
    return if stats.empty?

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

  def dump_locations # :nodoc:
    return unless trace_exit_locations_enabled?

    filename = "zjit_exit_locations.dump"
    dump_exit_locations(filename)

    $stderr.puts("ZJIT exit locations dumped to `#{filename}`.")
  end
end
