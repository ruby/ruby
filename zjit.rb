# frozen_string_literal: true

# This module allows for introspection of ZJIT, CRuby's just-in-time compiler.
# Everything in the module is highly implementation specific and the API might
# be less stable compared to the standard library.
#
# This module may not exist if ZJIT does not support the particular platform
# for which CRuby is built.
module RubyVM::ZJIT
  # Avoid calling a Ruby method here to avoid interfering with compilation tests
  if Primitive.rb_zjit_stats_enabled_p
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
  def stats(key = nil)
    stats = Primitive.rb_zjit_stats(key)
    return stats if stats.nil? || !key.nil?

    if stats.key?(:vm_insns_count) && stats.key?(:zjit_insns_count)
      stats[:total_insns_count] = stats[:vm_insns_count] + stats[:zjit_insns_count]
      stats[:ratio_in_zjit] = 100.0 * stats[:zjit_insns_count] / stats[:total_insns_count]
    end

    stats
  end

  # Get the summary of ZJIT statistics as a String
  def stats_string
    buf = +"***ZJIT: Printing ZJIT statistics on exit***\n"
    stats = self.stats

    print_counters_with_prefix(prefix: 'failed_', prompt: 'compilation failure reasons', buf:, stats:)
    print_counters([
      :compiled_iseq_count,
      :compilation_failure,

      :compile_time_ns,
      :profile_time_ns,
      :gc_time_ns,
      :invalidation_time_ns,

      :total_insns_count,
      :vm_insns_count,
      :zjit_insns_count,
      :ratio_in_zjit,
    ], buf:, stats:)

    buf
  end

  # Outputs counters into +buf+.
  def print_counters(keys, buf:, stats:)
    left_pad = keys.map(&:size).max + 1
    keys.each do |key|
      # Some stats like vm_insns_count and ratio_in_zjit are not supported on the release build
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

  # Similar to #print_counters but only includes keys that start with +prefix+.
  def print_counters_with_prefix(buf:, stats:, prefix:, prompt:)
    keys = stats.keys.select { |key| key.start_with?(prefix) && stats[key] > 0 }
    unless keys.empty?
      buf << "#{prompt}:\n"
      print_counters(keys, buf:, stats:)
    end
  end

  # Assert that any future ZJIT compilation will return a function pointer
  def assert_compiles # :nodoc:
    Primitive.rb_zjit_assert_compiles
  end

  # :stopdoc:
  private

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
