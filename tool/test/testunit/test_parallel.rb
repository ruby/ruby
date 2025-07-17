# frozen_string_literal: false
require 'test/unit'
require 'timeout'

module TestParallel
  PARALLEL_RB = "#{__dir__}/../../lib/test/unit/parallel.rb"
  TESTS = "#{__dir__}/tests_for_parallel"
  # use large timeout for --jit-wait
  TIMEOUT = EnvUtil.apply_timeout_scale(100)

  def self.timeout(n, &blk)
    start_time = Time.now
    Timeout.timeout(n, &blk)
  rescue Timeout::Error
    end_time = Time.now
    raise Timeout::Error, "execution expired (start: #{ start_time }, end: #{ end_time })"
  end

  class TestParallelWorker < Test::Unit::TestCase
    def setup
      i, @worker_in = IO.pipe
      @worker_out, o = IO.pipe
      @worker_pid = spawn(*@__runner_options__[:ruby], PARALLEL_RB,
                          "--ruby", @__runner_options__[:ruby].join(" "),
                          "-j", "t1", "-v", out: o, in: i)
      [i,o].each(&:close)
    end

    def teardown
      if @worker_pid && @worker_in
        begin
          begin
            @worker_in.puts "quit normal"
          rescue IOError, Errno::EPIPE
          end
          ::TestParallel.timeout(2) do
            Process.waitpid(@worker_pid)
          end
        rescue Timeout::Error
          begin
            Process.kill(:KILL, @worker_pid)
          rescue Errno::ESRCH
          end
        end
      end
    ensure
      begin
        @worker_in.close
        @worker_out.close
      rescue Errno::EPIPE
        # may already broken and rescue'ed in above code
      end
    end

    def test_run
      ::TestParallel.timeout(TIMEOUT) do
        assert_match(/^ready/,@worker_out.gets)
        @worker_in.puts "run #{TESTS}/ptest_first.rb test"
        assert_match(/^okay/,@worker_out.gets)
        assert_match(/^start/,@worker_out.gets)
        assert_match(/^record/,@worker_out.gets)
        assert_match(/^p/,@worker_out.gets)
        assert_match(/^done/,@worker_out.gets)
        assert_match(/^ready/,@worker_out.gets)
      end
    end

    def test_run_multiple_testcase_in_one_file
      ::TestParallel.timeout(TIMEOUT) do
        assert_match(/^ready/,@worker_out.gets)
        @worker_in.puts "run #{TESTS}/ptest_second.rb test"
        assert_match(/^okay/,@worker_out.gets)
        assert_match(/^start/,@worker_out.gets)
        assert_match(/^record/,@worker_out.gets)
        assert_match(/^p/,@worker_out.gets)
        assert_match(/^done/,@worker_out.gets)
        assert_match(/^start/,@worker_out.gets)
        assert_match(/^record/,@worker_out.gets)
        assert_match(/^p/,@worker_out.gets)
        assert_match(/^done/,@worker_out.gets)
        assert_match(/^ready/,@worker_out.gets)
      end
    end

    def test_accept_run_command_multiple_times
      ::TestParallel.timeout(TIMEOUT) do
        assert_match(/^ready/,@worker_out.gets)
        @worker_in.puts "run #{TESTS}/ptest_first.rb test"
        assert_match(/^okay/,@worker_out.gets)
        assert_match(/^start/,@worker_out.gets)
        assert_match(/^record/,@worker_out.gets)
        assert_match(/^p/,@worker_out.gets)
        assert_match(/^done/,@worker_out.gets)
        assert_match(/^ready/,@worker_out.gets)
        @worker_in.puts "run #{TESTS}/ptest_second.rb test"
        assert_match(/^okay/,@worker_out.gets)
        assert_match(/^start/,@worker_out.gets)
        assert_match(/^record/,@worker_out.gets)
        assert_match(/^p/,@worker_out.gets)
        assert_match(/^done/,@worker_out.gets)
        assert_match(/^start/,@worker_out.gets)
        assert_match(/^record/,@worker_out.gets)
        assert_match(/^p/,@worker_out.gets)
        assert_match(/^done/,@worker_out.gets)
        assert_match(/^ready/,@worker_out.gets)
      end
    end

    def test_p
      ::TestParallel.timeout(TIMEOUT) do
        @worker_in.puts "run #{TESTS}/ptest_first.rb test"
        while buf = @worker_out.gets
          break if /^p (.+?)$/ =~ buf
        end
        assert_not_nil($1, "'p' was not found")
        assert_match(/TestA#test_nothing_test = \d+\.\d+ s = \.\n/, $1.chomp.unpack1("m"))
      end
    end

    def test_done
      ::TestParallel.timeout(TIMEOUT) do
        @worker_in.puts "run #{TESTS}/ptest_forth.rb test"
        while buf = @worker_out.gets
          break if /^done (.+?)$/ =~ buf
        end
        assert_not_nil($1, "'done' was not found")

        result = Marshal.load($1.chomp.unpack1("m"))
        tests, asserts, reports, failures, loadpaths, suite = result
        assert_equal(5, tests)
        assert_equal(12, asserts)
        assert_kind_of(Array, reports)
        assert_kind_of(Array, failures)
        assert_kind_of(Array, loadpaths)
        reports.sort_by! {|_, t| t}
        assert_kind_of(Array, reports[1])
        assert_kind_of(Test::Unit::AssertionFailedError, reports[0][2])
        assert_kind_of(Test::Unit::PendedError, reports[1][2])
        assert_kind_of(Test::Unit::PendedError, reports[2][2])
        assert_kind_of(Exception, reports[3][2])
        assert_equal("TestE", suite)
      end
    end

    def test_quit
      ::TestParallel.timeout(TIMEOUT) do
        @worker_in.puts "quit normal"
        assert_match(/^bye$/m,@worker_out.read)
      end
    end
  end

  class TestParallel < Test::Unit::TestCase
    def spawn_runner(*opt_args, jobs: "t1")
      @test_out, o = IO.pipe
      @test_pid = spawn(*@__runner_options__[:ruby], TESTS+"/runner.rb",
                        "--ruby", @__runner_options__[:ruby].join(" "),
                        "-j", jobs, *opt_args, out: o, err: o)
      o.close
    end

    def teardown
      begin
        if @test_pid
          ::TestParallel.timeout(2) do
            Process.waitpid(@test_pid)
          end
        end
      rescue Timeout::Error
        Process.kill(:KILL, @test_pid) if @test_pid
      ensure
        @test_out&.close
      end
    end

    def test_ignore_jzero
      spawn_runner(jobs: "0")
      ::TestParallel.timeout(TIMEOUT) {
        assert_match(/Error: parameter of -j option should be greater than 0/,@test_out.read)
      }
    end

    def test_should_run_all_without_any_leaks
      spawn_runner
      buf = ::TestParallel.timeout(TIMEOUT) {@test_out.read}
      assert_match(/^9 tests/,buf)
    end

    def test_should_retry_failed_on_workers
      spawn_runner "--retry"
      buf = ::TestParallel.timeout(TIMEOUT) {@test_out.read}
      assert_match(/^Retrying\.+$/,buf)
    end

    def test_no_retry_option
      spawn_runner "--no-retry"
      buf = ::TestParallel.timeout(TIMEOUT) {@test_out.read}
      refute_match(/^Retrying\.+$/,buf)
      assert_match(/^ +\d+\) Failure:\nTestD#test_fail_at_worker/,buf)
    end

    def test_jobs_status
      spawn_runner "--jobs-status"
      buf = ::TestParallel.timeout(TIMEOUT) {@test_out.read}
      assert_match(/\d+=ptest_(first|second|third|forth) */,buf)
    end

    def test_separate
      # this test depends to --jobs-status
      spawn_runner "--jobs-status", "--separate"
      buf = ::TestParallel.timeout(TIMEOUT) {@test_out.read}
      assert(buf.scan(/^\[\s*\d+\/\d+\]\s*(\d+?)=/).flatten.uniq.size > 1,
             message("retried tests should run in different processes") {buf})
    end

    def test_hungup
      spawn_runner "--worker-timeout=1", "--retry", "test4test_hungup.rb"
      buf = ::TestParallel.timeout(TIMEOUT) {@test_out.read}
      assert_match(/^Retrying hung up testcases\.+$/, buf)
      assert_match(/^2 tests,.* 0 failures,/, buf)
    end
  end
end
