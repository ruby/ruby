#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "open3"
require "shellwords"
require "fileutils"
require "rbconfig"
require "time"

DEFAULT_BENCHMARKS = %w[
  erubi-rails
  shipit
  liquid-render
  hexapdf
  railsbench
  lobsters
].freeze

ResultRow = Struct.new(:name, :perf_ratio, :rss_ratio, :stars, keyword_init: true)
RunResult = Struct.new(:key, :label, :rows, :perf_geomean, :rss_geomean, :log_path, keyword_init: true)


def parse_ratio_with_stars(text)
  if /\A([0-9]+(?:\.[0-9]+)?)(?:\s+\((\*+)\))?\z/ =~ text.strip
    [Float($1), ($2 || "").size]
  else
    [nil, 0]
  end
end

def geomean(values)
  return 0.0 if values.empty?

  Math.exp(values.sum { |value| Math.log(value) } / values.size)
end

def merge_opts(*parts)
  parts.flat_map { |part| Shellwords.split(part.to_s) }.join(" ")
end

def engine_spec(label, ruby_path, runtime_opts)
  opts = runtime_opts.to_s.strip
  return "#{label}::#{ruby_path}" if opts.empty?

  "#{label}::#{ruby_path} #{opts}"
end

def run_and_parse!(ruby_bench_dir:, bench_args:, benchmarks:, key:, label:, master_engine:, experiment_engine:, output_dir:)
  command = [
    RbConfig.ruby,
    "run_benchmarks.rb",
    "-e", master_engine,
    "-e", experiment_engine,
    *bench_args,
    *benchmarks,
  ]

  puts "\n== #{label} =="
  puts "[command] #{command.shelljoin}"

  output, status = Open3.capture2e(*command, chdir: ruby_bench_dir)
  timestamp = Time.now.utc.strftime("%Y%m%d-%H%M%S")
  log_path = File.join(output_dir, "#{timestamp}-#{key}.log")
  File.write(log_path, output)

  unless status.success?
    warn output
    raise "benchmark run failed: #{label} (log: #{log_path})"
  end

  rows = []
  has_rss_columns = output.include?("RSS master/experiment")
  benchmark_set = benchmarks.to_set
  output.each_line do |line|
    cols = line.rstrip.split(/\s{2,}/)
    next unless cols.size >= 8
    next unless cols[1].include?("±") && cols[3].include?("±")

    name = cols[0]
    next unless benchmark_set.include?(name)

    perf_ratio, stars = parse_ratio_with_stars(cols[6])
    rss_ratio, = parse_ratio_with_stars(cols[7])
    next if perf_ratio.nil? || rss_ratio.nil?

    rows << ResultRow.new(name: name, perf_ratio: perf_ratio, rss_ratio: rss_ratio, stars: stars)
  end

  if rows.empty?
    unless has_rss_columns
      raise "benchmark output is missing RSS columns for #{label}; ensure --rss is passed (log: #{log_path})"
    end
    raise "failed to parse benchmark table for #{label} (log: #{log_path})"
  end

  RunResult.new(
    key: key,
    label: label,
    rows: rows,
    perf_geomean: geomean(rows.map(&:perf_ratio)),
    rss_geomean: geomean(rows.map(&:rss_ratio)),
    log_path: log_path,
  )
end

def print_result(result)
  puts format("perf geomean: %.4f", result.perf_geomean)
  puts format("rss  geomean: %.4f", result.rss_geomean)
end

def evaluate_gates(result, min_perf_geomean:, min_rss_geomean:, max_perf_regression:, regression_stars:)
  perf_ok = result.perf_geomean >= min_perf_geomean
  rss_ok = result.rss_geomean >= min_rss_geomean

  severe_regressions = result.rows.select do |row|
    row.perf_ratio < max_perf_regression && row.stars >= regression_stars
  end

  severe_ok = severe_regressions.empty?

  puts "gates:"
  puts "  perf geomean >= #{min_perf_geomean}: #{perf_ok ? 'PASS' : 'FAIL'}"
  puts "  rss  geomean >= #{min_rss_geomean}: #{rss_ok ? 'PASS' : 'FAIL'}"
  puts "  no perf ratio < #{max_perf_regression} with stars >= #{regression_stars}: #{severe_ok ? 'PASS' : 'FAIL'}"

  unless severe_ok
    puts "  severe regressions:"
    severe_regressions.sort_by(&:perf_ratio).each do |row|
      puts format("    - %-16s ratio=%.3f stars=%d rss=%.3f", row.name, row.perf_ratio, row.stars, row.rss_ratio)
    end
  end

  perf_ok && rss_ok && severe_ok
end

def print_feature_attribution(on_result, off_result)
  puts "\nFeature attribution (feature OFF minus feature ON, positive means OFF is better):"

  on_by_name = on_result.rows.to_h { |row| [row.name, row] }
  off_by_name = off_result.rows.to_h { |row| [row.name, row] }
  shared_names = on_by_name.keys & off_by_name.keys

  deltas = shared_names.map do |name|
    on = on_by_name.fetch(name)
    off = off_by_name.fetch(name)
    {
      name: name,
      perf_delta: off.perf_ratio - on.perf_ratio,
      rss_delta: off.rss_ratio - on.rss_ratio,
      on_perf: on.perf_ratio,
      off_perf: off.perf_ratio,
      on_rss: on.rss_ratio,
      off_rss: off.rss_ratio,
    }
  end

  perf_sorted = deltas.sort_by { |delta| -delta[:perf_delta] }
  rss_sorted = deltas.sort_by { |delta| -delta[:rss_delta] }

  puts "  top perf penalties from feature ON:"
  perf_sorted.first(3).each do |delta|
    puts format("    - %-16s delta=%+.3f (on=%.3f off=%.3f)",
                delta[:name], delta[:perf_delta], delta[:on_perf], delta[:off_perf])
  end

  puts "  top rss penalties from feature ON:"
  rss_sorted.first(3).each do |delta|
    puts format("    - %-16s delta=%+.3f (on=%.3f off=%.3f)",
                delta[:name], delta[:rss_delta], delta[:on_rss], delta[:off_rss])
  end
end

options = {
  ruby_bench: nil,
  master_ruby: nil,
  experiment_ruby: nil,
  feature_on_opts: "",
  feature_off_opts: nil,
  bench_args: "--warmup=3 --bench=10 --rss",
  benchmarks: DEFAULT_BENCHMARKS.dup,
  min_perf_geomean: 0.995,
  min_rss_geomean: 1.0,
  max_perf_regression: 0.97,
  regression_stars: 2,
  output_dir: "tmp/retire-pages-bench",
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options] [BENCHMARK ...]"

  opts.on("--ruby-bench DIR", "Path to ruby-bench checkout") do |value|
    options[:ruby_bench] = value
  end

  opts.on("--master-ruby PATH", "Path to master ruby binary") do |value|
    options[:master_ruby] = value
  end

  opts.on("--experiment-ruby PATH", "Path to experiment ruby binary") do |value|
    options[:experiment_ruby] = value
  end

  opts.on("--feature-on-opts ARGS", "Runtime opts to enable feature (default: none)") do |value|
    options[:feature_on_opts] = value
  end

  opts.on("--feature-off-opts ARGS", "Runtime opts to disable feature") do |value|
    options[:feature_off_opts] = value
  end

  opts.on("--bench-args ARGS", "Args passed to run_benchmarks.rb (default: #{options[:bench_args]})") do |value|
    options[:bench_args] = value
  end

  opts.on("--benchmarks x,y,z", Array, "Benchmark names (default: #{DEFAULT_BENCHMARKS.join(',')})") do |value|
    options[:benchmarks] = value
  end

  opts.on("--min-perf-geomean FLOAT", Float, "Gate: min perf geomean (default: #{options[:min_perf_geomean]})") do |value|
    options[:min_perf_geomean] = value
  end

  opts.on("--min-rss-geomean FLOAT", Float, "Gate: min RSS geomean (default: #{options[:min_rss_geomean]})") do |value|
    options[:min_rss_geomean] = value
  end

  opts.on("--max-perf-regression FLOAT", Float, "Gate: max allowed perf regression ratio (default: #{options[:max_perf_regression]})") do |value|
    options[:max_perf_regression] = value
  end

  opts.on("--regression-stars N", Integer, "Gate: minimum significance stars for perf regression (default: #{options[:regression_stars]})") do |value|
    options[:regression_stars] = value
  end

  opts.on("--output-dir DIR", "Directory for raw logs (default: #{options[:output_dir]})") do |value|
    options[:output_dir] = value
  end
end

parser.parse!(ARGV)
options[:benchmarks] = ARGV unless ARGV.empty?

required = %i[ruby_bench master_ruby experiment_ruby]
missing = required.select { |key| options[key].nil? || options[key].empty? }
unless missing.empty?
  warn "Missing required options: #{missing.join(', ')}"
  warn parser
  exit 1
end

require "set"

options[:ruby_bench] = File.expand_path(options[:ruby_bench])
options[:master_ruby] = File.expand_path(options[:master_ruby])
options[:experiment_ruby] = File.expand_path(options[:experiment_ruby])

unless File.exist?(File.join(options[:ruby_bench], "run_benchmarks.rb"))
  warn "ruby-bench checkout not found at #{options[:ruby_bench]} (missing run_benchmarks.rb)"
  exit 1
end

[options[:master_ruby], options[:experiment_ruby]].each do |ruby_path|
  unless File.executable?(ruby_path)
    warn "ruby binary is not executable: #{ruby_path}"
    exit 1
  end
end

FileUtils.mkdir_p(options[:output_dir])

bench_args = Shellwords.split(options[:bench_args])
unless bench_args.include?("--rss")
  bench_args << "--rss"
  puts "[info] Added --rss to bench args to collect memory data"
end
benchmarks = options[:benchmarks]
feature_toggle_mode = !options[:feature_off_opts].to_s.empty?

scenarios = [
  {
    key: "yjit-on",
    label: feature_toggle_mode ? "YJIT ON / feature ON" : "YJIT ON",
    master_opts: "--yjit",
    experiment_opts: merge_opts("--yjit", options[:feature_on_opts]),
  },
  {
    key: "yjit-off",
    label: feature_toggle_mode ? "YJIT OFF / feature ON" : "YJIT OFF",
    master_opts: "--disable-yjit",
    experiment_opts: merge_opts("--disable-yjit", options[:feature_on_opts]),
  },
]

if feature_toggle_mode
  scenarios << {
    key: "yjit-on-feature-off",
    label: "YJIT ON / feature OFF",
    master_opts: "--yjit",
    experiment_opts: merge_opts("--yjit", options[:feature_off_opts]),
  }
  scenarios << {
    key: "yjit-off-feature-off",
    label: "YJIT OFF / feature OFF",
    master_opts: "--disable-yjit",
    experiment_opts: merge_opts("--disable-yjit", options[:feature_off_opts]),
  }
end

results = {}

scenarios.each do |scenario|
  results[scenario[:key]] = run_and_parse!(
    ruby_bench_dir: options[:ruby_bench],
    bench_args: bench_args,
    benchmarks: benchmarks,
    key: scenario[:key],
    label: scenario[:label],
    master_engine: engine_spec("master", options[:master_ruby], scenario[:master_opts]),
    experiment_engine: engine_spec("experiment", options[:experiment_ruby], scenario[:experiment_opts]),
    output_dir: options[:output_dir],
  )
  print_result(results.fetch(scenario[:key]))
end

puts "\n== Gate evaluation =="
pass_yjit_on = evaluate_gates(
  results.fetch("yjit-on"),
  min_perf_geomean: options[:min_perf_geomean],
  min_rss_geomean: options[:min_rss_geomean],
  max_perf_regression: options[:max_perf_regression],
  regression_stars: options[:regression_stars],
)

pass_yjit_off = evaluate_gates(
  results.fetch("yjit-off"),
  min_perf_geomean: options[:min_perf_geomean],
  min_rss_geomean: options[:min_rss_geomean],
  max_perf_regression: options[:max_perf_regression],
  regression_stars: options[:regression_stars],
)

if feature_toggle_mode
  print_feature_attribution(
    results.fetch("yjit-on"),
    results.fetch("yjit-on-feature-off"),
  )
  print_feature_attribution(
    results.fetch("yjit-off"),
    results.fetch("yjit-off-feature-off"),
  )
end

puts "\nRaw logs:"
results.each_value do |result|
  puts "  - #{result.key}: #{result.log_path}"
end

if pass_yjit_on && pass_yjit_off
  puts "\nPASS: experiment meets gates in both YJIT modes."
  exit 0
else
  puts "\nFAIL: experiment does not meet gates in one or more YJIT modes."
  exit 1
end
