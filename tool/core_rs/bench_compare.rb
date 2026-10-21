#!/usr/bin/env ruby
# frozen_string_literal: true

# bench_compare.rb - Compares performance of Ruby builds with and without Rust ports.
#
# Usage:
#   ruby tool/core_rs/bench_compare.rb --with-ports ./ruby --without-ports ../build-c/ruby [options]
#
# Options:
#   --with-ports PATH       Path to Ruby binary or build directory compiled --with-rust-ports
#   --without-ports PATH    Path to Ruby binary or build directory compiled --without-rust-ports
#   --threshold PERCENT     Maximum allowed performance regression percentage (default: 10.0)
#   --repeat COUNT          Number of iterations per benchmark (default: 3)
#   --benchmarks LIST       Comma-separated list of benchmark files to run

require 'optparse'
require 'open3'
require 'fileutils'

DEFAULT_THRESHOLD_PERCENT = 10.0
DEFAULT_REPEAT_COUNT = 3

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

def measure_execution(ruby_bin, bench_file, repeat_count)
  times = []
  repeat_count.times do
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    _stdout, stderr, status = Open3.capture3(ruby_bin, bench_file)
    t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    unless status.success?
      warn "Error running #{ruby_bin} on #{bench_file}:\n#{stderr}"
      return nil
    end

    times << (t1 - t0)
  end

  times.min
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
  puts '-' * 80

  format_header = "%-25s %-18s %-18s %-12s %-10s"
  format_row    = "%-25s %-18s %-18s %-12s %-10s"

  puts sprintf(format_header, 'Benchmark', 'C Fallback (s)', 'Rust Ports (s)', 'Diff (%)', 'Status')
  puts '-' * 80

  total_without = 0.0
  total_with = 0.0
  any_benchmark_failed = false

  bench_files.each do |bench_file|
    bench_name = File.basename(bench_file)

    t_without = measure_execution(without_exe, bench_file, options[:repeat])
    t_with    = measure_execution(with_exe, bench_file, options[:repeat])

    if t_without.nil? || t_with.nil?
      puts sprintf(format_row, bench_name, 'ERROR', 'ERROR', 'N/A', 'FAIL')
      any_benchmark_failed = true
      next
    end

    total_without += t_without
    total_with += t_with

    diff_pct = ((t_with - t_without) / t_without) * 100.0
    status = diff_pct > options[:threshold] ? 'FAIL' : 'PASS'

    if status == 'FAIL'
      any_benchmark_failed = true
    end

    diff_str = sprintf('%+.2f%%', diff_pct)
    puts sprintf(format_row, bench_name, sprintf('%.4fs', t_without), sprintf('%.4fs', t_with), diff_str, status)
  end

  puts '-' * 80
  overall_diff_pct = ((total_with - total_without) / total_without) * 100.0
  overall_status = (overall_diff_pct > options[:threshold] || any_benchmark_failed) ? 'FAIL' : 'PASS'
  overall_diff_str = sprintf('%+.2f%%', overall_diff_pct)

  puts sprintf(format_row, 'TOTAL / OVERALL', sprintf('%.4fs', total_without), sprintf('%.4fs', total_with), overall_diff_str, overall_status)
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
