# frozen_string_literal: true

# Distribute the parallel bundler-spec workers by measured per-file runtime
# instead of file size, with no change to turbo_tests or parallel_tests and
# without touching the synced spec/bin/parallel_rspec. The test-bundler-parallel
# recipe requires this file and calls install! just before loading the stock
# parallel_rspec; install! prepends the grouper (parent) and appends the recorder
# to RSPEC_EXECUTABLE so each worker records (see bundler_runtime_recorder.rb).
# The grouping/recording logic lives under tool/, which sync-default-gems never
# copies, so the rubygems side stays untouched.
#
# turbo_tests only feeds a runtime log to the grouper when invoked with the bare
# "spec" path (TurboTests::CLI passes files: ["spec"] only when given no
# positional arg), which the build never does: the recipe passes an absolute
# spec/bundler path, so grouping falls back to file size and the single heaviest
# file becomes the long pole. We reopen the one grouper hook that size path uses,
# ParallelTests::RSpec::Runner.sort_by_filesize, and return runtime weights when
# the previous run left us data. Its argument is the already-expanded file list,
# so nothing here re-globs or re-reads it.

module BundlerRuntimeGrouping
  WORKER_LOGS = ".[0-9]*"

  module_function

  # Per-worker log base. Under the (gitignored) source tmp so it survives between
  # runs; overridable via BUNDLER_SPEC_RUNTIME_LOG.
  def log_base
    ENV["BUNDLER_SPEC_RUNTIME_LOG"] ||
      File.expand_path("../../tmp/bundler_runtime_rspec.log", __dir__)
  end

  # Append one "<seconds>\t<file>" line for a finished example to this worker's
  # own log ("<base>.<TEST_ENV_NUMBER>"); a single shared file would hit Windows
  # cross-process sharing violations. Called from the worker (see recorder).
  def record(example, seconds)
    worker = ENV["TEST_ENV_NUMBER"].to_s
    worker = "1" if worker.empty?
    File.write("#{log_base}.#{worker}",
               "#{format("%.4f", seconds)}\t#{example.metadata[:file_path]}\n", mode: "a")
  rescue StandardError
    # never let runtime logging break a test run
  end

  # {canonical_path => seconds} summed across the previous run's worker logs,
  # memoized before this run overwrites them. Empty on the first run.
  def runtimes
    @runtimes ||= Dir.glob(log_base + WORKER_LOGS).each_with_object(Hash.new(0.0)) do |path, sums|
      File.foreach(path) do |line|
        seconds, tab, file = line.chomp.partition("\t")
        sums[canonical(file)] += seconds.to_f unless tab.empty?
      end
    rescue StandardError
      sums
    end
  end

  # cwd-independent key: from "spec/bundler/" on, forward slashes. Recorded paths
  # are rspec-relative ("./spec/bundler/..."); grouped paths are absolute.
  def canonical(path)
    normalized = path.tr("\\", "/")
    i = normalized.index("spec/bundler/")
    i ? normalized[i..] : normalized
  end

  # Called once in the parent before parallel_rspec loads (spec/bundler/support
  # must already be required so parallel_tests is on the load path). Reads the
  # previous run, clears the logs, prepends the grouper, and arranges for each
  # worker to record by appending the recorder to RSPEC_EXECUTABLE.
  def install!
    require "fileutils"
    require "parallel_tests/rspec/runner"
    FileUtils.mkdir_p(File.dirname(log_base))
    runtimes # capture the previous run before clearing
    Dir.glob(log_base + WORKER_LOGS).each { |f| File.delete(f) rescue nil }
    ParallelTests::RSpec::Runner.singleton_class.prepend(SortHook)
    if ENV["RSPEC_EXECUTABLE"]
      recorder = File.expand_path("bundler_runtime_recorder.rb", __dir__)
      ENV["RSPEC_EXECUTABLE"] = "#{ENV["RSPEC_EXECUTABLE"]} -r#{recorder}"
    end
  rescue StandardError, LoadError => e
    warn "parallel_rspec: runtime-based grouping disabled (#{e.class}: #{e.message})"
  end

  module SortHook
    def sort_by_filesize(tests)
      rt = BundlerRuntimeGrouping.runtimes
      return super if rt.empty?
      tests.sort!
      known = tests.map { |t| rt[BundlerRuntimeGrouping.canonical(t)] }.select(&:positive?)
      return super unless known.size * 1.5 > tests.size # parallel_tests' own threshold
      average = known.sum / known.size
      tests.map! do |t|
        seconds = rt[BundlerRuntimeGrouping.canonical(t)]
        [t, seconds.positive? ? seconds : average]
      end
    end
  end
end
