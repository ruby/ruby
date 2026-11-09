#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare the measured Callgrind dumps, not ruby-bench's wall-clock timings.
require 'json'
require 'optparse'
require 'shellwords'

module ZJITCallgrind
  class << self
    def instruction_count(path)
      events = summary = nil
      File.foreach(path) do |line|
        if line.start_with?('events:')
          events = line.split.drop(1)
        elsif line.start_with?('summary:')
          summary = line.split.drop(1).map { |value| Integer(value, 10) }
        end
      end
      index = events&.index('Ir')
      unless index && summary && summary[index]
        raise ArgumentError, "Missing Ir summary in #{path}"
      end
      count = summary[index]
      raise ArgumentError, "Empty instruction count in #{path}" unless count > 0
      count
    end

    def read_counts(directory, executable)
      data = JSON.parse(File.read(File.join(directory, 'results.json')))
      benchmarks = data.fetch('raw_data').fetch(executable)
      raise ArgumentError, "No benchmarks in #{directory}" if benchmarks.empty?

      benchmarks.each_with_object({}) do |(name, result), counts|
        # ruby-bench records the exact profile template in each command line.
        # The harness's explicit dump is .1; the process-exit file contains
        # post-measurement activity and must not be added to the measured count.
        options = Shellwords.split(result.fetch('command_line')).grep(/\A--callgrind-out-file=/)
        raise ArgumentError, "Missing profile path for #{name}" unless options.size == 1

        template = File.basename(options.first.split('=', 2).last)
        pattern = File.join(directory, template.gsub('%p', '[0-9]*') + '.1')
        profiles = Dir.glob(pattern)
        unless profiles.size == 1
          raise ArgumentError, "Expected one measured profile for #{name}, got #{profiles.inspect}"
        end
        unless result.fetch('bench').size == 1
          raise ArgumentError, "Expected one measured iteration for #{name}"
        end
        counts[name] = instruction_count(profiles.first)
      end
    end

    def format_count(count)
      count.to_s.reverse.scan(/.{1,3}/).join(',').reverse
    end

    def report(base, pr, base_sha, head_sha, bench_rev)
      raise ArgumentError, 'Base and PR benchmark sets differ' unless base.keys.sort == pr.keys.sort

      lines = [
        '<!-- zjit-callgrind -->',
        '## ZJIT Callgrind comparison',
        '',
        "Base: `#{base_sha}` → PR: `#{head_sha}`",
        "ruby-bench: `#{bench_rev}` (PR #576 Callgrind harness).",
        '',
        '40 warmup iterations, then 1 measured iteration; both Rubies use `--zjit`.',
        'Instruction counts (Ir), not elapsed time. Negative change means fewer instructions.',
        'Setup and warmup are excluded; compilation and GC during measurement are included.',
        '',
        '| Benchmark | Base instructions | PR instructions | Change |',
        '| :--- | ---: | ---: | ---: |',
      ]
      base.keys.sort.each do |name|
        # Benchmark names come from the pinned suite, not arbitrary Markdown.
        raise ArgumentError, "Invalid benchmark name: #{name.inspect}" unless /\A[a-zA-Z0-9_-]+\z/.match?(name)

        change = (pr.fetch(name).fdiv(base.fetch(name)) - 1) * 100
        lines << format('| %s | %s | %s | %+.2f%% |', name,
                        format_count(base.fetch(name)), format_count(pr.fetch(name)), change)
      end
      lines.concat(['', 'Counts may vary with GC, code layout, and workload nondeterminism; this is not a wall-time speedup estimate.'])
      lines.join("\n")
    end

    def main(argv)
      options = {}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{$PROGRAM_NAME} RESULTS --base SHA --head SHA --bench-rev SHA"
        opts.on('--base SHA') { |value| options[:base] = value }
        opts.on('--head SHA') { |value| options[:head] = value }
        opts.on('--bench-rev SHA') { |value| options[:bench_rev] = value }
      end
      parser.parse!(argv)
      [:base, :head, :bench_rev].each do |key|
        raise OptionParser::MissingArgument, "--#{key.to_s.tr('_', '-')}" unless options.key?(key)
      end
      raise OptionParser::InvalidArgument, 'expected one results directory' unless argv.size == 1

      directory = argv.first
      puts report(read_counts(File.join(directory, 'base'), 'base'),
                  read_counts(File.join(directory, 'pr'), 'pr'),
                  options.fetch(:base), options.fetch(:head), options.fetch(:bench_rev))
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    ZJITCallgrind.main(ARGV)
  rescue OptionParser::ParseError => error
    abort error.message
  end
end
