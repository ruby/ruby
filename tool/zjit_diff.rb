#!/usr/bin/env ruby
require 'fileutils'
require 'optparse'
require 'tmpdir'

GitRef = Struct.new(:ref, :commit_hash)

BEFORE_NAME = 'ruby-zjit-before'.freeze
AFTER_NAME = 'ruby-zjit-after'.freeze
DATA_FILENAME = File.join('data', 'zjit_diff')
RUBY_BENCH_REPO_URL = 'https://github.com/ruby/ruby-bench.git'.freeze

def log_info(msg)
  puts "\e[32m#{msg}\e[0m"
end

def log_error(msg)
  warn "\e[31mError: #{msg}\e[0m"
end

def run(*args, **options)
  system(*args, options.merge(exception: true))
end

def macos?
  Gem::Platform.local == 'darwin'
end

class RubyWorktree
  attr_reader :name, :path

  BREW_REQUIRED_PACKAGES = %w[openssl readline libyaml].freeze

  def initialize(name:, ref:, force_reconfigure: false)
    @name = name
    @path = File.join(Dir.tmpdir, name)
    @ref = ref
    @force_reconfigure = force_reconfigure

    setup_worktree
  end

  def build
    Dir.chdir(@path) do
      if !File.exist?('Makefile') || @force_reconfigure
        run('./autogen.sh')

        prefix = File.join(Dir.home, '.rubies', name)

        cmd = [
          './configure',
          '--enable-zjit=dev',
          "--prefix=#{prefix}",
          '--disable-install-doc'
        ]

        if macos?
          brew_prefixes = BREW_REQUIRED_PACKAGES.map do |pkg|
            `brew --prefix #{pkg}`.strip
          end
          cmd << "--with-opt-dir=#{brew_prefixes.join(':')}"
        end

        run(*cmd)
      end
      run('make', '-j', 'miniruby')
      run('make', 'install')
    end
  end

  private

  def setup_worktree
    if Dir.exist?(@path)
      log_info "Existing worktree found at #{@path}"
      Dir.chdir(@path) do
        run('git', 'checkout', @ref.commit_hash)
      end
    else
      log_info "Creating worktree for ref '#{@ref.ref}' at #{@path}"
      run('git', 'worktree', 'add', '--detach', @path, @ref.commit_hash)
    end
  end
end

def parse_ref(ref)
  out = `git rev-parse --verify #{ref}`
  return nil unless $?.success?

  GitRef.new(ref: ref, commit_hash: out.strip)
end

def setup_ruby_bench
  path = File.join(Dir.tmpdir, 'ruby-bench')
  if Dir.exist?(path)
    log_info('ruby-bench already cloned, pulling from upstream')
    Dir.chdir(path) do
      run('git', 'pull')
    end
  else
    log_info("ruby-bench not cloned yet, cloning repository to #{path}")
    run('git', 'clone', RUBY_BENCH_REPO_URL, path)
  end
  Dir.chdir(path) do
    run('bundle', 'install')
  end
  path
end

def clean
  [BEFORE_NAME, AFTER_NAME].each do |name|
    path = File.join(Dir.tmpdir, name)
    if Dir.exist?(path)
      log_info "Removing worktree at #{path}"
      system('git', 'worktree', 'remove', '--force', path)
    end
  end

  bench_path = File.join(Dir.tmpdir, 'ruby-bench')
  return unless Dir.exist?(bench_path)

  log_info "Removing ruby-bench clone at #{bench_path}"
  FileUtils.rm_rf(bench_path)
end

options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on('--before REF', 'Git ref for ruby (before)') do |ref|
    git_ref = parse_ref ref
    if git_ref.nil?
      log_error "'#{ref}' is not a valid git ref"
      exit 1
    end

    options[:before] = git_ref
  end

  opts.on('--after REF', 'Git ref for ruby (after)') do |ref|
    git_ref = parse_ref ref
    if ref.nil?
      log_error "'#{ref}' is not a valid git ref"
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
    options[:bench_args] = bench_args
  end

  opts.on('--force-reconfigure', 'Force running ./configure again for existing worktrees even if Makefile exists') do
    options[:force_reconfigure] = true
  end

  opts.on('--clean', 'Remove temporary git worktrees and ruby-bench clone and exit') do
    options[:clean] = true
  end

  options[:name_filters] = []
end.parse!

options[:name_filters] += ARGV unless ARGV.empty?

if options[:clean]
  clean
  exit(0)
end

# Build both versions
before = RubyWorktree.new(name: BEFORE_NAME, ref: options[:before], force_reconfigure: options[:force_reconfigure])
before.build
after = RubyWorktree.new(name: AFTER_NAME, ref: options[:after], force_reconfigure: options[:force_reconfigure])
after.build

# Setup ruby bench and run the benchmarks
ruby_bench_path = options[:bench_path] || setup_ruby_bench

Dir.chdir(ruby_bench_path) do
  run('./run_benchmarks.rb',
      '--chruby',
      "#{BEFORE_NAME} --zjit-stats;#{AFTER_NAME} --zjit-stats",
      '--out-name',
      DATA_FILENAME,
      *options[:bench_args],
      *options[:name_filters])

  run('./misc/zjit_diff.rb', "#{DATA_FILENAME}.json")
end
