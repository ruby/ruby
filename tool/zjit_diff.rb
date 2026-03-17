#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'optparse'
require 'tmpdir'
require 'logger'
require 'digest'
require 'shellwords'

GitRef = Struct.new(:ref, :commit_hash)

RUBIES_DIR = File.join(Dir.home, '.zjit-diff')
RESULTS_CACHE_DIR = File.join(Dir.home, '.zjit-diff', 'results')
BEFORE_NAME = 'ruby-zjit-before'
AFTER_NAME = 'ruby-zjit-after'

LOG = Logger.new($stderr)

def macos?
  Gem::Platform.local == 'darwin'
end

class CommandRunner
  def initialize(quiet: false)
    @quiet = quiet
  end

  def cmd(*args, **options)
    options[:out] ||= @quiet ? File::NULL : $stderr
    options = options.merge(exception: true)
    system(*args, **options)
  end
end

class ZJITDiff
  DATA_FILENAME = File.join('data', 'zjit_diff')
  RUBY_BENCH_REPO_URL = 'https://github.com/ruby/ruby-bench.git'

  def initialize(before_hash:, after_hash:, runner:, options:)
    @before_hash = before_hash
    @after_hash = after_hash
    @runner = runner
    @options = options
  end

  def bench!
    LOG.info('Running benchmarks')
    ruby_bench_path = @options[:bench_path] || setup_ruby_bench
    run_benchmarks(ruby_bench_path)
  end

  private

  def results_cache_key(rev_hash)
    key_parts = [rev_hash, @options[:bench_args], @options[:name_filters]].inspect
    Digest::MD5.hexdigest(key_parts)
  end

  def run_rev(ruby_bench_path, name, rev_hash)
    cache_file = File.join(RESULTS_CACHE_DIR, "#{results_cache_key(rev_hash)}.json")

    if File.exist?(cache_file) && !@options[:force_rerun]
      LOG.info("Using cached results for #{name} from #{cache_file}")
      return JSON.parse(File.read(cache_file))
    end

    out_name = File.join('data', "zjit_diff_#{name}")
    Dir.chdir(ruby_bench_path) do
      @runner.cmd({ 'RUBIES_DIR' => RUBIES_DIR },
                  './run_benchmarks.rb',
                  '--chruby',
                  "#{name}::#{rev_hash} --zjit-stats",
                  '--out-name',
                  out_name,
                  *@options[:bench_args],
                  *@options[:name_filters])
    end

    result = JSON.parse(File.read(File.join(ruby_bench_path, "#{out_name}.json")))
    FileUtils.mkdir_p(RESULTS_CACHE_DIR)
    File.write(cache_file, JSON.generate(result))
    LOG.info("Cached results for #{name} to #{cache_file}")
    result
  end

  def run_benchmarks(ruby_bench_path)
    before_data = run_rev(ruby_bench_path, 'before', @before_hash)
    after_data = run_rev(ruby_bench_path, 'after', @after_hash)

    merged = {
      'metadata' => before_data['metadata'].merge(after_data['metadata']),
      'raw_data' => before_data['raw_data'].merge(after_data['raw_data']),
    }

    merged_path = File.join(ruby_bench_path, "#{DATA_FILENAME}.json")
    FileUtils.mkdir_p(File.dirname(merged_path))
    File.write(merged_path, JSON.generate(merged))

    Dir.chdir(ruby_bench_path) do
      @runner.cmd('./misc/zjit_diff.rb', "#{DATA_FILENAME}.json", out: $stdout)
    end
  end

  def setup_ruby_bench
    path = File.join(Dir.tmpdir, 'ruby-bench')
    if Dir.exist?(path)
      LOG.info('ruby-bench already cloned, pulling from upstream')
      Dir.chdir(path) do
        @runner.cmd('git', 'pull')
      end
    else
      LOG.info("ruby-bench not cloned yet, cloning repository to #{path}")
      @runner.cmd('git', 'clone', RUBY_BENCH_REPO_URL, path)
    end
    path
  end
end

class RubyWorktree
  attr_reader :hash

  BREW_REQUIRED_PACKAGES = %w[openssl readline libyaml].freeze

  def initialize(name:, ref:, runner:, force_rebuild: false)
    @path = File.join(Dir.tmpdir, name)
    @ref = ref
    @force_rebuild = force_rebuild
    @runner = runner
    @hash = nil

    setup_worktree
  end

  def build!
    Dir.chdir(@path) do
      configure_cmd_args = ['--enable-zjit=stats', '--disable-install-doc']
      if macos?
        brew_prefixes = BREW_REQUIRED_PACKAGES.map do |pkg|
          `brew --prefix #{pkg}`.strip
        end
        configure_cmd_args << "--with-opt-dir=#{brew_prefixes.join(':')}"
      end
      configure_cmd_hash = Digest::MD5.hexdigest(configure_cmd_args.join(''))

      build_cmd_args = ['-j', 'miniruby']
      build_cmd_hash = Digest::MD5.hexdigest(build_cmd_args.join(''))

      @hash = "#{configure_cmd_hash}-#{build_cmd_hash}-#{@ref.commit_hash}"
      prefix = File.join(RUBIES_DIR, @hash)

      if Dir.exist?(prefix) && !@force_rebuild
        LOG.info("Found existing build for #{@ref.ref}, skipping build")
        return
      end

      @runner.cmd('./autogen.sh')

      cmd = [
        './configure',
        *configure_cmd_args,
        "--prefix=#{prefix}"
      ]

      @runner.cmd(*cmd)
      @runner.cmd('make', *build_cmd_args)
      @runner.cmd('make', 'install')
    end
  end

  private

  def setup_worktree
    if Dir.exist?(@path)
      LOG.info("Existing worktree found at #{@path}")
      Dir.chdir(@path) do
        @runner.cmd('git', 'checkout', @ref.commit_hash)
      end
    else
      LOG.info("Creating worktree for ref '#{@ref.ref}' at #{@path}")
      @runner.cmd('git', 'worktree', 'add', '--detach', @path, @ref.commit_hash)
    end
  end
end

def clean!
  [BEFORE_NAME, AFTER_NAME].each do |name|
    path = File.join(Dir.tmpdir, name)
    if Dir.exist?(path)
      LOG.info("Removing worktree at #{path}")
      system('git', 'worktree', 'remove', '--force', path)
    end
  end

  if Dir.exist?(RUBIES_DIR)
    LOG.info("Removing ruby installations and cached results from #{RUBIES_DIR}")
    FileUtils.rm_rf(RUBIES_DIR)
  end

  bench_path = File.join(Dir.tmpdir, 'ruby-bench')
  return unless Dir.exist?(bench_path)

  LOG.info("Removing ruby-bench clone at #{bench_path}")
  FileUtils.rm_rf(bench_path)
end

def parse_ref(ref)
  out = `git rev-parse --verify #{ref}`
  return nil unless $?.success?

  GitRef.new(ref: ref, commit_hash: out.strip)
end

DEFAULT_BENCHMARKS = %w[lobsters railsbench].freeze

options = {}

subtext = <<~HELP
  Subcommands:
     bench :  Run benchmarks
     clean :  Clean temporary files created by benchmarks
  See '#{$PROGRAM_NAME} COMMAND --help' for more information on a specific command.
HELP

top_level = OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.separator('')
  opts.separator(subtext)
end

subcommands = {
  'bench' => OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options] <benchmarks to run>"

    opts.on('--before REF', 'Git ref for ruby (before)') do |ref|
      git_ref = parse_ref ref
      if git_ref.nil?
        warn "Error: '#{ref}' is not a valid git ref"
        exit 1
      end

      options[:before] = git_ref
    end

    opts.on('--after REF', 'Git ref for ruby (after)') do |ref|
      git_ref = parse_ref ref
      if git_ref.nil?
        warn "Error: '#{ref}' is not a valid git ref"
        exit 1
      end

      options[:after] = git_ref
    end

    opts.on('--bench-path PATH',
            'Path to an existing ruby-bench repository clone ' \
            '(if not specified, ruby-bench will be cloned automatically to a temporary directory)') do |path|
      options[:bench_path] = path
    end

    opts.on('--bench-args ARGS', 'Args to pass to ruby-bench') do |bench_args|
      options[:bench_args] = bench_args.shellsplit
    end

    opts.on('--force-rebuild',
            'Force building ruby again instead of using even if existing builds exist in the cache at ~/.diffs') do
      options[:force_rebuild] = true
    end

    opts.on('--force-rerun', 'Force re-running benchmarks even if cached results exist') do
      options[:force_rerun] = true
    end

    opts.on('--quiet', 'Silence output of commands except for benchmark result') do
      options[:quiet] = true
    end

    opts.separator('')
    opts.separator('If no benchmarks are specified, the benchmarks that will be run are:')
    opts.separator(DEFAULT_BENCHMARKS.join(', '))
  end,
  'clean' => OptionParser.new do |opts|
  end
}

if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.4')
  abort "Error: zjit_diff.rb requires Ruby 3.4 or later (running #{RUBY_VERSION})"
end

top_level.order!
command = ARGV.shift
subcommands[command].order!

case command
when 'bench'
  options[:name_filters] = ARGV.empty? ? DEFAULT_BENCHMARKS : ARGV
  options[:after] ||= parse_ref('HEAD')

  runner = CommandRunner.new(quiet: options[:quiet])

  before = RubyWorktree.new(name: BEFORE_NAME,
                            ref: options[:before],
                            runner: runner,
                            force_rebuild: options[:force_rebuild])
  before.build!
  after = RubyWorktree.new(name: AFTER_NAME,
                           ref: options[:after],
                           runner: runner,
                           force_rebuild: options[:force_rebuild])
  after.build!

  zjit_diff = ZJITDiff.new(runner: runner, before_hash: before.hash, after_hash: after.hash, options: options)
  zjit_diff.bench!
when 'clean'
  clean!
end
