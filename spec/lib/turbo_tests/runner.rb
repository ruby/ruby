# frozen_string_literal: true

require "json"
require "parallel_tests/rspec/runner"

require_relative "../utils/hash_extension"

module TurboTests
  class Runner
    using CoreExtensions

    def self.run(opts = {})
      files = opts[:files]
      formatters = opts[:formatters]
      tags = opts[:tags]

      start_time = opts.fetch(:start_time) { RSpec::Core::Time.now }
      runtime_log = opts.fetch(:runtime_log, nil)
      verbose = opts.fetch(:verbose, false)
      fail_fast = opts.fetch(:fail_fast, nil)
      count = opts.fetch(:count, nil)
      seed = opts.fetch(:seed)
      seed_used = !seed.nil?

      if verbose
        warn "VERBOSE"
      end

      reporter = Reporter.from_config(formatters, start_time, seed, seed_used)

      new(
        reporter: reporter,
        files: files,
        tags: tags,
        runtime_log: runtime_log,
        verbose: verbose,
        fail_fast: fail_fast,
        count: count,
        seed: seed,
        seed_used: seed_used,
      ).run
    end

    def initialize(opts)
      @reporter = opts[:reporter]
      @files = opts[:files]
      @tags = opts[:tags]
      @runtime_log = opts[:runtime_log] || "tmp/turbo_rspec_runtime.log"
      @verbose = opts[:verbose]
      @fail_fast = opts[:fail_fast]
      @count = opts[:count]
      @seed = opts[:seed]
      @seed_used = opts[:seed_used]

      @load_time = 0
      @load_count = 0
      @failure_count = 0

      @messages = Thread::Queue.new
      @threads = []
      @error = false
    end

    def run
      @num_processes = [
        ParallelTests.determine_number_of_processes(@count),
        ParallelTests::RSpec::Runner.tests_with_size(@files, {}).size
      ].min

      use_runtime_info = @files == ["spec"]

      group_opts = {}

      if use_runtime_info
        group_opts[:runtime_log] = @runtime_log
      else
        group_opts[:group_by] = :filesize
      end

      tests_in_groups =
        ParallelTests::RSpec::Runner.tests_in_groups(
          @files,
          @num_processes,
          **group_opts
        )

      subprocess_opts = {
        record_runtime: use_runtime_info,
      }

      @reporter.report(tests_in_groups) do |reporter|
        wait_threads = tests_in_groups.map.with_index do |tests, process_id|
          start_regular_subprocess(tests, process_id + 1, **subprocess_opts)
        end

        handle_messages

        @threads.each(&:join)

        if @reporter.failed_examples.empty? && wait_threads.map(&:value).all?(&:success?)
          0
        else
          # From https://github.com/serpapi/turbo_tests/pull/20/
          wait_threads.map { |thread| thread.value.exitstatus }.max
        end
      end
    end

    private

    def start_regular_subprocess(tests, process_id, **opts)
      start_subprocess(
        {"TEST_ENV_NUMBER" => process_id.to_s},
        @tags.map { |tag| "--tag=#{tag}" },
        tests,
        process_id,
        **opts
      )
    end

    def start_subprocess(env, extra_args, tests, process_id, record_runtime:)
      if tests.empty?
        @messages << {
          type: "exit",
          process_id: process_id,
        }
      else
        env["RSPEC_FORMATTER_OUTPUT_ID"] = SecureRandom.uuid
        env["RUBYOPT"] = ["-I#{File.expand_path("..", __dir__)}", ENV["RUBYOPT"]].compact.join(" ")
        env["RSPEC_SILENCE_FILTER_ANNOUNCEMENTS"] = "1"

        if ENV["PARALLEL_TESTS_EXECUTABLE"]
          command_name = ENV["PARALLEL_TESTS_EXECUTABLE"].split
        elsif ENV["BUNDLE_BIN_PATH"]
          command_name = [ENV["BUNDLE_BIN_PATH"], "exec", "rspec"]
        else
          command_name = "rspec"
        end

        record_runtime_options =
          if record_runtime
            [
              "--format", "ParallelTests::RSpec::RuntimeLogger",
              "--out", @runtime_log,
            ]
          else
            []
          end

        seed_option = if @seed_used
          [
            "--seed", @seed,
          ]
        else
          []
        end

        command = [
          *command_name,
          *extra_args,
          *seed_option,
          "--format", "TurboTests::JsonRowsFormatter",
          *record_runtime_options,
          *tests,
        ]

        if @verbose
          command_str = [
            env.map { |k, v| "#{k}=#{v}" }.join(" "),
            command.join(" "),
          ].select { |x| x.size > 0 }.join(" ")

          warn "Process #{process_id}: #{command_str}"
        end

        stdin, stdout, stderr, wait_thr = Open3.popen3(env, *command)
        stdin.close

        @threads <<
          Thread.new do
            stdout.each_line do |line|
              result = line.split(env["RSPEC_FORMATTER_OUTPUT_ID"])

              output = result.shift
              print(output) unless output.empty?

              message = result.shift
              next unless message

              message = JSON.parse(message, symbolize_names: true)
              message[:process_id] = process_id
              @messages << message
            end

            @messages << { type: "exit", process_id: process_id }
          end

        @threads << start_copy_thread(stderr, STDERR)

        @threads << Thread.new do
          unless wait_thr.value.success?
            @messages << { type: "error" }
          end
        end

        wait_thr
      end
    end

    def start_copy_thread(src, dst)
      Thread.new do
        loop do
          msg = src.readpartial(4096)
        rescue EOFError
          src.close
          break
        else
          dst.write(msg)
        end
      end
    end

    def handle_messages
      exited = 0

      loop do
        message = @messages.pop
        case message[:type]
        when "example_passed"
          example = FakeExample.from_obj(message[:example])
          @reporter.example_passed(example)
        when "group_started"
          @reporter.group_started(message[:group].to_struct)
        when "group_finished"
          @reporter.group_finished
        when "example_pending"
          example = FakeExample.from_obj(message[:example])
          @reporter.example_pending(example)
        when "load_summary"
          message = message[:summary]
          # NOTE: notifications order and content is not guaranteed hence the fetch
          #       and count increment tracking to get the latest accumulated load time
          @reporter.load_time = message[:load_time] if message.fetch(:count, 0) > @load_count
        when "example_failed"
          example = FakeExample.from_obj(message[:example])
          @reporter.example_failed(example)
          @failure_count += 1
          if fail_fast_met
            @threads.each(&:kill)
            break
          end
        when "message"
          if message[:message].include?("An error occurred") || message[:message].include?("occurred outside of examples")
            @reporter.error_outside_of_examples(message[:message])
            @error = true
          else
            @reporter.message(message[:message])
          end
        when "seed"
        when "close"
        when "error"
          # Do nothing
          nil
        when "exit"
          exited += 1
          if exited == @num_processes
            break
          end
        else
          STDERR.puts("Unhandled message in main process: #{message}")
        end

        STDOUT.flush
      end
    rescue Interrupt
    end

    def fail_fast_met
      !@fail_fast.nil? && @failure_count >= @fail_fast
    end
  end
end
