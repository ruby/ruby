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
    at_exit { print_stats }
  end
end

class << RubyVM::ZJIT
  # Check if ZJIT is enabled
  def enabled?
    Primitive.cexpr! 'RBOOL(rb_zjit_enabled_p)'
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

    # Show exit reasons, ordered by the typical amount of exits for the prefix at the time
    print_counters_with_prefix(prefix: 'unhandled_yarv_insn_', prompt: 'unhandled YARV insns', buf:, stats:, limit: 20)
    print_counters_with_prefix(prefix: 'compile_error_', prompt: 'compile error reasons', buf:, stats:, limit: 20)
    print_counters_with_prefix(prefix: 'exit_', prompt: 'side exit reasons', buf:, stats:, limit: 20)
    print_counters_with_prefix(prefix: 'dynamic_send_type_', prompt: 'dynamic send types', buf:, stats:, limit: 20)

    # Show the most important stats ratio_in_zjit at the end
    print_counters([
      :dynamic_send_count,

      :compiled_iseq_count,
      :failed_iseq_count,

      :compile_time_ns,
      :profile_time_ns,
      :gc_time_ns,
      :invalidation_time_ns,

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
    left_pad = counters.keys.map(&:size).max
    right_pad = counters.values.map { |value| number_with_delimiter(value).size }.max
    total = counters.values.sum

    counters = counters.to_a
    counters.sort_by! { |_, value| -value }
    counters = counters.first(limit) if limit

    buf << "Top-#{counters.size} " if limit
    buf << "#{prompt}"
    buf << " (%.1f%% of total #{number_with_delimiter(total)})" % (100.0 * counters.map(&:last).sum / total) if limit
    buf << ":\n"
    counters.each do |key, value|
      padded_key = key.rjust(left_pad, ' ')
      padded_value = number_with_delimiter(value).rjust(right_pad, ' ')
      buf << "  #{padded_key}: #{padded_value} (%4.1f%%)\n" % (100.0 * value / total)
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
end
