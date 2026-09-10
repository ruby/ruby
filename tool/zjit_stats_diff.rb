#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare two `--zjit-stats=FILE.json` dumps and report only the counters whose
# values changed significantly.
#
#   ruby tool/zjit_stats_diff.rb before.json after.json
#   ruby tool/zjit_stats_diff.rb --threshold=10 --min-diff=1000 before.json after.json
#   ruby tool/zjit_stats_diff.rb --markdown before.json after.json >> "$GITHUB_STEP_SUMMARY"
#
# A counter is "significant" when the relative change exceeds --threshold AND the
# absolute change exceeds --min-diff. Both gates are needed: the percentage alone
# makes 1 -> 2 look like a 100% regression, and the absolute difference alone
# hides small-but-total changes in rarely-hit counters.

require 'json'
require 'optparse'

class ZJITStatsDiff
  DEFAULT_THRESHOLD = 5.0 # percent
  DEFAULT_MIN_DIFF = 100  # absolute counter units
  DEFAULT_LIMIT = 20      # rows per per-entity section

  # Counters keyed by iseq/cfunc/method name. There are thousands of these and
  # they are dominated by whatever incidental code the benchmark happened to
  # run, so they get their own length-limited sections instead of competing with
  # the aggregate counters for attention.
  PER_ENTITY_SECTIONS = [
    ['iseq_calls_count_',     'most called JIT functions'],
    ['not_inlined_cfuncs_',   'not inlined C methods'],
    ['not_annotated_cfuncs_', 'not annotated C methods'],
    ['ccall_',                'calls to C functions from JIT code'],
  ].freeze

  # Wall-clock counters. These drift between runs of the *same* build (measured
  # at ~5% on lobsters), so they are reported separately rather than mixed in
  # with the deterministic counts.
  TIMING_SUFFIX = '_time_ns'

  Row = Struct.new(:key, :before, :after, :diff, :pct, :kind, keyword_init: true)

  def initialize(before_path, after_path, options = {})
    @before_label = options[:before_label] || File.basename(before_path, '.json')
    @after_label = options[:after_label] || File.basename(after_path, '.json')
    @before = normalize(load(before_path))
    @after = normalize(load(after_path))
    @threshold = options.fetch(:threshold, DEFAULT_THRESHOLD)
    @min_diff = options.fetch(:min_diff, DEFAULT_MIN_DIFF)
    @limit = options.fetch(:limit, DEFAULT_LIMIT)
    @markdown = options[:markdown]
  end

  def report
    all_keys = (@before.keys | @after.keys)
    per_entity_keys, aggregate_keys = all_keys.partition { |key| section_for(key) }
    timing_keys, count_keys = aggregate_keys.partition { |key| key.end_with?(TIMING_SUFFIX) }

    out = +''
    out << header(all_keys.size)

    counts = significant(count_keys)
    timings = significant(timing_keys)
    per_entity = PER_ENTITY_SECTIONS.map do |prefix, title|
      [prefix, title, significant(per_entity_keys.select { |key| key.start_with?(prefix) })]
    end

    if counts.empty? && timings.empty? && per_entity.all? { |_, _, rows| rows.empty? }
      out << "\nNo counter changed by more than #{fmt_pct_threshold} " \
             "(and #{fmt_num(@min_diff)} in absolute terms).\n"
      return out
    end

    out << table('Counters', counts) unless counts.empty?
    out << table('Timing (noisy: varies between runs of the same build)', timings, collapsed: true) unless timings.empty?
    per_entity.each do |prefix, title, rows|
      next if rows.empty?
      out << table(title, rows, strip_prefix: prefix, limit: @limit, collapsed: true)
    end
    out
  end

  private

  # A truncated or empty dump means the benchmark died before writing its stats,
  # which is worth saying out loud rather than reporting as a JSON syntax error.
  def load(path)
    JSON.parse(File.read(path))
  rescue JSON::ParserError => e
    raise "#{path} is not a valid --zjit-stats dump (did the process exit early?): #{e.message}"
  end

  # Anonymous classes and modules are named after their address
  # (`#<Module:0x00007f1a>#foo`), which differs on every run and would otherwise
  # show up as a pair of bogus "new"/"gone" counters. Collapse the address and
  # sum the counters that merge as a result.
  def normalize(stats)
    stats.each_with_object({}) do |(key, value), acc|
      key = key.gsub(/0x\h+/, '0x…')
      if acc.key?(key) && acc[key].is_a?(Numeric) && value.is_a?(Numeric)
        acc[key] += value
      else
        acc[key] = value
      end
    end
  end

  def section_for(key)
    PER_ENTITY_SECTIONS.find { |prefix, _| key.start_with?(prefix) }
  end

  def significant(keys)
    keys.filter_map { |key| row_for(key) }.sort_by do |row|
      # Appeared/disappeared counters first (no meaningful percentage), then by
      # the size of the relative change.
      [row.pct ? 1 : 0, -(row.pct&.abs || row.diff.abs)]
    end
  end

  def row_for(key)
    before = @before.fetch(key, 0)
    after = @after.fetch(key, 0)
    return nil unless before.is_a?(Numeric) && after.is_a?(Numeric)

    diff = after - before
    return nil if diff.zero?

    # --min-diff is expressed in counter units, which is meaningless for the
    # float ratio counters (a 1-point move in ratio_in_zjit is a big deal).
    ratio = before.is_a?(Float) || after.is_a?(Float)
    return nil if !ratio && diff.abs <= @min_diff

    if before.zero?
      Row.new(key: key, before: before, after: after, diff: diff, pct: nil, kind: :new)
    elsif after.zero?
      Row.new(key: key, before: before, after: after, diff: diff, pct: -100.0, kind: :gone)
    else
      pct = diff.fdiv(before) * 100
      return nil unless pct.abs > @threshold
      Row.new(key: key, before: before, after: after, diff: diff, pct: pct, kind: :changed)
    end
  end

  def header(compared)
    if @markdown
      <<~MD
        ## ZJIT stats: `#{@after_label}` vs `#{@before_label}`

        Compared #{fmt_num(compared)} counters. Showing changes over #{fmt_pct_threshold} and #{fmt_num(@min_diff)} absolute.
      MD
    else
      <<~TXT
        ZJIT stats: #{@after_label} vs #{@before_label}
        Compared #{fmt_num(compared)} counters. Showing changes over #{fmt_pct_threshold} and #{fmt_num(@min_diff)} absolute.
      TXT
    end
  end

  def fmt_pct_threshold
    format('%g%%', @threshold)
  end

  def table(title, rows, strip_prefix: nil, limit: nil, collapsed: false)
    shown = limit ? rows.first(limit) : rows
    omitted = rows.size - shown.size
    @markdown ? md_table(title, shown, omitted, strip_prefix, collapsed) : txt_table(title, shown, omitted, strip_prefix)
  end

  def md_table(title, rows, omitted, strip_prefix, collapsed)
    out = +"\n"
    heading = "#{title} (#{rows.size + omitted})"
    out << (collapsed ? "<details><summary>#{heading}</summary>\n\n" : "### #{heading}\n\n")
    out << "| counter | #{@before_label} | #{@after_label} | change |\n|---|--:|--:|--:|\n"
    rows.each do |row|
      out << "| `#{display_key(row.key, strip_prefix)}` | #{fmt_value(row.key, row.before)} | " \
             "#{fmt_value(row.key, row.after)} | #{fmt_change(row)} |\n"
    end
    out << "\n_... and #{fmt_num(omitted)} more_\n" if omitted.positive?
    out << "\n</details>\n" if collapsed
    out
  end

  def txt_table(title, rows, omitted, strip_prefix)
    out = +"\n#{title} (#{rows.size + omitted})\n"
    out << ('-' * 78) << "\n"
    width = rows.map { |row| display_key(row.key, strip_prefix).size }.max
    rows.each do |row|
      out << format("  %-*s %14s -> %14s  %s\n", width, display_key(row.key, strip_prefix),
                    fmt_value(row.key, row.before), fmt_value(row.key, row.after), fmt_change(row))
    end
    out << "  ... and #{fmt_num(omitted)} more\n" if omitted.positive?
    out
  end

  def display_key(key, strip_prefix)
    key = key.delete_prefix(strip_prefix) if strip_prefix
    key.sub(/#{TIMING_SUFFIX}\z/, '_time')
  end

  def fmt_change(row)
    case row.kind
    when :new then 'new'
    when :gone then 'gone'
    else format('%s%+.1f%%', row.pct.positive? ? '▲' : '▼', row.pct)
    end
  end

  def fmt_value(key, value)
    if key.end_with?(TIMING_SUFFIX)
      format('%sms', fmt_num((value / 1_000_000.0).round))
    elsif key.end_with?('_bytes')
      fmt_bytes(value)
    elsif value.is_a?(Float)
      format('%.2f', value)
    else
      fmt_num(value)
    end
  end

  def fmt_num(value)
    value.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
  end

  def fmt_bytes(bytes)
    units = [['GiB', 1 << 30], ['MiB', 1 << 20], ['KiB', 1 << 10]]
    unit, scale = units.find { |_, s| bytes.abs >= s }
    unit ? format('%.1f%s', bytes.to_f / scale, unit) : "#{bytes}B"
  end
end

if __FILE__ == $PROGRAM_NAME
  options = {}
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{File.basename($PROGRAM_NAME)} [options] BEFORE.json AFTER.json"

    opts.on('--threshold=PCT', Float,
            "Minimum relative change to report (default: #{ZJITStatsDiff::DEFAULT_THRESHOLD})") do |pct|
      options[:threshold] = pct
    end
    opts.on('--min-diff=N', Integer,
            "Minimum absolute change to report (default: #{ZJITStatsDiff::DEFAULT_MIN_DIFF})") do |n|
      options[:min_diff] = n
    end
    opts.on('--limit=N', Integer,
            "Rows per per-entity section (default: #{ZJITStatsDiff::DEFAULT_LIMIT}, 0 for all)") do |n|
      options[:limit] = n.zero? ? nil : n
    end
    opts.on('--all', 'Report every changed counter') do
      options[:threshold] = 0.0
      options[:min_diff] = 0
      options[:limit] = nil
    end
    opts.on('--markdown', 'Emit GitHub-flavored Markdown') { options[:markdown] = true }
    opts.on('--before-label=NAME', 'Label for the baseline column') { |n| options[:before_label] = n }
    opts.on('--after-label=NAME', 'Label for the comparison column') { |n| options[:after_label] = n }
    opts.on('-h', '--help', 'Print this message') do
      puts opts
      exit
    end
  end
  parser.parse!

  unless ARGV.size == 2
    warn parser.help
    exit 1
  end

  begin
    print ZJITStatsDiff.new(ARGV[0], ARGV[1], options).report
  rescue RuntimeError, SystemCallError => e
    abort "#{File.basename($PROGRAM_NAME)}: #{e.message}"
  end
end
