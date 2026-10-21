#!/usr/bin/env ruby
# frozen_string_literal: true

# bench_compare.rb - Compares performance of Ruby builds with and without Rust ports.
#
# Methodology:
# 1. Startup overhead subtraction: Measures startup runtime using `ruby -e0` for both binaries.
#    Subtracts the median startup overhead from gross execution times to yield net benchmark times.
# 2. Interleaved execution: For each benchmark and during startup measurement, runs of the
#    without-ports (C fallback) and with-ports (Rust ports) binaries are interleaved across iterations
#    to eliminate environmental drift or host load bias.
# 3. Stable median: Runs each benchmark `repeat` times (default: 10) and calculates the median net execution time.
# 4. Geometric mean decision: Calculates the ratio of net execution times (with_ports / without_ports)
#    for each benchmark, then computes the geometric mean across all benchmarks.
# 5. Threshold & Warning Policy: Default regression threshold is 10.0%. The performance gate fails
#    if and only if the geometric mean regression percentage exceeds the threshold. Individual
#    benchmarks that exceed the threshold are flagged as warnings ('WARN') and do not fail the gate on their own.
#
# Usage:
#   ruby tool/core_rs/bench_compare.rb --with-ports ./ruby --without-ports ../build-c/ruby [options]
#
# Options:
#   --with-ports PATH       Path to Ruby binary or build directory compiled --with-rust-ports
#   --without-ports PATH    Path to Ruby binary or build directory compiled --without-rust-ports
#   --threshold PERCENT     Maximum allowed performance regression percentage (default: 10.0)
#   --repeat COUNT          Number of iterations per benchmark (default: 10)
#   --benchmarks LIST       Comma-separated list of benchmark files to run

require 'optparse'
require 'open3'
require 'fileutils'

DEFAULT_THRESHOLD_PERCENT = 10.0
DEFAULT_REPEAT_COUNT = 10

REPO_ROOT = File.expand_path('../../', __dir__)

DEFAULT_BENCHMARK_FILES = [
  'benchmark/app_fib.rb',
  'benchmark/app_factorial.rb',
  'benchmark/app_strconcat.rb',
  'benchmark/so_ackermann.rb',
  'benchmark/so_sieve.rb'
].map { |rel| File.join(REPO_ROOT, rel) }.freeze

def resolve_executable(path)
  return nil if path.nil? || path.to_s.empty?

  expanded = File.expand_path(path)
  if File.directory?(expanded)
    ruby_exe = File.join(expanded, 'ruby')
    miniruby_exe = File.join(expanded, 'miniruby')
    if File.file?(ruby_exe) && File.executable?(ruby_exe)
      ruby_exe
    elsif File.file?(miniruby_exe) && File.executable?(miniruby_exe)
      miniruby_exe
    else
      nil
    end
  elsif File.file?(expanded) && File.executable?(expanded)
    expanded
  else
    nil
  end
end

def run_command_once(ruby_bin, args)
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  _stdout, stderr, status = Open3.capture3(ruby_bin, *args)
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  unless status.success?
    warn "Error running #{ruby_bin} #{args.join(' ')}:\n#{stderr}"
    return nil
  end

  t1 - t0
end

def measure_interleaved(without_exe, with_exe, args, repeat_count)
  times_without = []
  times_with = []

  repeat_count.times do |i|
    # Interleave order to balance any system state bias across iterations
    first_exe, second_exe = if i.even?
                              [without_exe, with_exe]
                            else
                              [with_exe, without_exe]
                            end

    t_first = run_command_once(first_exe, args)
    t_second = run_command_once(second_exe, args)

    return [nil, nil] if t_first.nil? || t_second.nil?

    if i.even?
      times_without << t_first
      times_with << t_second
    else
      times_with << t_first
      times_without << t_second
    end
  end

  [times_without, times_with]
end

def median(array)
  return 0.0 if array.nil? || array.empty?

  sorted = array.sort
  len = sorted.length
  if len.odd?
    sorted[len / 2]
  else
    (sorted[(len / 2) - 1] + sorted[len / 2]) / 2.0
  end
end

def parse_options
  options = {
    with_ports: nil,
    without_ports: nil,
    threshold: DEFAULT_THRESHOLD_PERCENT,
    repeat: DEFAULT_REPEAT_COUNT,
    benchmarks: nil
  }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} --with-ports PATH --without-ports PATH [options]"

    opts.on('--with-ports PATH', 'Path to Ruby executable or build directory (with Rust ports)') do |v|
      options[:with_ports] = v
    end

    opts.on('--without-ports PATH', 'Path to Ruby executable or build directory (without Rust ports / C fallback)') do |v|
      options[:without_ports] = v
    end

    opts.on('--threshold PERCENT', Float, "Regression threshold percentage (default: #{DEFAULT_THRESHOLD_PERCENT})") do |v|
      options[:threshold] = v
    end

    opts.on('--repeat COUNT', Integer, "Number of runs per benchmark (default: #{DEFAULT_REPEAT_COUNT})") do |v|
      options[:repeat] = v
    end

    opts.on('--benchmarks LIST', Array, 'Comma-separated list of benchmark files') do |v|
      options[:benchmarks] = v
    end

    opts.on('-h', '--help', 'Prints this help') do
      puts opts
      exit 0
    end
  end

  parser.parse!

  if options[:with_ports].nil? || options[:without_ports].nil?
    puts parser
    exit 1
  end

  options
end

def main
  options = parse_options

  with_exe = resolve_executable(options[:with_ports])
  without_exe = resolve_executable(options[:without_ports])

  if with_exe.nil?
    abort "Error: --with-ports binary not found or not executable at '#{options[:with_ports]}'"
  end

  if without_exe.nil?
    abort "Error: --without-ports binary not found or not executable at '#{options[:without_ports]}'"
  end

  bench_files = if options[:benchmarks] && !options[:benchmarks].empty?
                  options[:benchmarks].map { |f| File.expand_path(f, REPO_ROOT) }
                else
                  DEFAULT_BENCHMARK_FILES
                end

  bench_files.each do |f|
    unless File.file?(f)
      abort "Error: Benchmark file not found at '#{f}'"
    end
  end

  puts '=' * 80
  puts 'Ruby on Rust Benchmark Performance Gate'
  puts '=' * 80
  puts "With Rust ports binary:    #{with_exe}"
  puts "Without Rust ports binary: #{without_exe}"
  puts "Iterations per benchmark:  #{options[:repeat]}"
  puts "Regression threshold:      #{options[:threshold]}%"

  # Measure ruby -e0 startup time (interleaved)
  startup_without_times, startup_with_times = measure_interleaved(without_exe, with_exe, ['-e', '0'], options[:repeat])
  if startup_without_times.nil? || startup_with_times.nil?
    abort 'Error measuring startup overhead (ruby -e0)'
  end

  startup_without_med = median(startup_without_times)
  startup_with_med = median(startup_with_times)

  puts sprintf('Startup overhead (ruby -e0): C: %.4fs, Rust: %.4fs', startup_without_med, startup_with_med)
  puts '-' * 80

  format_header = '%-25s %-18s %-18s %-12s %-10s'
  format_row    = '%-25s %-18s %-18s %-12s %-10s'

  puts sprintf(format_header, 'Benchmark', 'C Net (s)', 'Rust Net (s)', 'Diff (%)', 'Status')
  puts '-' * 80

  any_benchmark_errored = false
  ratios = []

  bench_files.each do |bench_file|
    bench_name = File.basename(bench_file)

    times_without, times_with = measure_interleaved(without_exe, with_exe, [bench_file], options[:repeat])

    if times_without.nil? || times_with.nil?
      puts sprintf(format_row, bench_name, 'ERROR', 'ERROR', 'N/A', 'FAIL')
      any_benchmark_errored = true
      next
    end

    gross_without = median(times_without)
    gross_with = median(times_with)

    net_without = [gross_without - startup_without_med, 0.000001].max
    net_with = [gross_with - startup_with_med, 0.000001].max

    ratio = net_with / net_without
    ratios << ratio

    diff_pct = (ratio - 1.0) * 100.0
    status = diff_pct > options[:threshold] ? 'WARN' : 'PASS'

    diff_str = sprintf('%+.2f%%', diff_pct)
    puts sprintf(format_row, bench_name, sprintf('%.4fs', net_without), sprintf('%.4fs', net_with), diff_str, status)
  end

  puts '-' * 80

  if ratios.empty? || any_benchmark_errored
    overall_status = 'FAIL'
    overall_diff_str = 'N/A'
    puts sprintf(format_row, 'GEOMETRIC MEAN / OVERALL', 'N/A', 'N/A', 'N/A', 'FAIL')
    puts '=' * 80
    puts 'PERFORMANCE GATE FAILED: One or more benchmarks errored during execution'
    exit 1
  end

  geomean_ratio = Math.exp(ratios.map { |r| Math.log(r) }.sum / ratios.size)
  overall_diff_pct = (geomean_ratio - 1.0) * 100.0
  overall_diff_str = sprintf('%+.2f%%', overall_diff_pct)

  overall_status = overall_diff_pct > options[:threshold] ? 'FAIL' : 'PASS'

  puts sprintf(format_row, 'GEOMETRIC MEAN / OVERALL', '', '', overall_diff_str, overall_status)
  puts '=' * 80

  if overall_status == 'FAIL'
    puts "PERFORMANCE GATE FAILED: Rust ports build regressed by #{overall_diff_str} (threshold: #{options[:threshold]}%)"
    exit 1
  else
    puts "PERFORMANCE GATE PASSED: Rust ports performance is within threshold (#{overall_diff_str} <= #{options[:threshold]}%)"
    exit 0
  end
end

main if __FILE__ == $PROGRAM_NAME
