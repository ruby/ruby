require 'test/unit'
require 'timeout'

module TestParallel
  PARALLEL_RB = "#{File.dirname(__FILE__)}/../../lib/test/unit/parallel.rb"
  TESTS = "#{File.dirname(__FILE__)}/tests_for_parallel"


  class TestParallelWorker < Test::Unit::TestCase
    def setup
      i, @worker_in = IO.pipe
      @worker_out, o = IO.pipe
      @worker_pid = spawn(*@options[:ruby], PARALLEL_RB,
                          "-j", "t1", "-v", out: o, in: i)
      [i,o].each(&:close)
    end

    def teardown
      begin
        @worker_in.puts "quit"
        timeout(2) do
          Process.waitpid(@worker_pid)
        end
      rescue IOError, Errno::EPIPE, Timeout::Error
        Process.kill(:KILL, @worker_pid)
      end
    end

    def test_run
      timeout(10) do
        assert_match(/^ready/,@worker_out.gets)
        @worker_in.puts "run #{TESTS}/test_first.rb ptest"
        assert_match(/^okay/,@worker_out.gets)
        assert_match(/^p/,@worker_out.gets)
        assert_match(/^done/,@worker_out.gets)
        assert_match(/^done/,@worker_out.gets)
        assert_match(/^ready/,@worker_out.gets)
      end
    end

    def test_run_multiple_testcase_in_one_file
      timeout(10) do
        assert_match(/^ready/,@worker_out.gets)
        @worker_in.puts "run #{TESTS}/test_second.rb ptest"
        assert_match(/^okay/,@worker_out.gets)
        assert_match(/^p/,@worker_out.gets)
        assert_match(/^done/,@worker_out.gets)
        assert_match(/^p/,@worker_out.gets)
        assert_match(/^done/,@worker_out.gets)
        assert_match(/^done/,@worker_out.gets)
        assert_match(/^ready/,@worker_out.gets)
      end
    end
    
    def test_accept_run_command_multiple_times
      timeout(10) do
        assert_match(/^ready/,@worker_out.gets)
        @worker_in.puts "run #{TESTS}/test_first.rb ptest"
        assert_match(/^okay/,@worker_out.gets)
        assert_match(/^p/,@worker_out.gets)
        assert_match(/^done/,@worker_out.gets)
        assert_match(/^done/,@worker_out.gets)
        assert_match(/^ready/,@worker_out.gets)
        @worker_in.puts "run #{TESTS}/test_second.rb ptest"
        assert_match(/^okay/,@worker_out.gets)
        assert_match(/^p/,@worker_out.gets)
        assert_match(/^done/,@worker_out.gets)
        assert_match(/^p/,@worker_out.gets)
        assert_match(/^done/,@worker_out.gets)
        assert_match(/^ready/,@worker_out.gets)
      end
    end

    def test_p
      timeout(10) do
        @worker_in.puts "run #{TESTS}/test_first.rb ptest"
        while buf = @worker_out.gets
          break if /^p (.+?)$/ =~ buf
        end
        assert_match(/TestA#ptest_nothing_test = \d+\.\d+ s = \.\n/, $1.chomp.unpack("m")[0])
      end
    end

    def test_done
      timeout(10) do
        @worker_in.puts "run #{TESTS}/test_forth.rb ptest"
        i = 0
        while buf = @worker_out.gets
          if /^done (.+?)$/ =~ buf
            i += 1
            break if i == 2 # Break at 2nd "done"
          end
        end

        result = Marshal.load($1.chomp.unpack("m")[0])

        assert_equal(result[0],3)
        assert_equal(result[1],2)
        assert_kind_of(Array,result[2])
        assert_kind_of(Array,result[3])
        assert_kind_of(Array,result[4])
        assert_match(/Skipped:$/,result[2][0])
        assert_match(/Failure:$/,result[2][1])
        assert_equal(result[5], "TestE")
      end
    end

    def test_quit
      timeout(10) do
        @worker_in.puts "quit"
        assert_match(/^bye$/m,@worker_out.read)
      end
    end

    def test_quit_in_test
      timeout(10) do
        @worker_in.puts "run #{TESTS}/test_third.rb ptest"
        @worker_in.puts "quit"
        assert_match(/^ready\nokay\nbye/m,@worker_out.read)
      end
    end
  end

  class TestParallel < Test::Unit::TestCase
    def spawn_runner(*opt_args)
      @test_out, o = IO.pipe
      @test_pid = spawn(*@options[:ruby], TESTS+"/runner.rb",
                        "-j","t2","-x","sleeping",*opt_args, out: o)
      o.close
    end

    def teardown
      begin
        if @test_pid
          timeout(2) do
            Process.waitpid(@test_pid)
          end
        end
      rescue Timeout::Error
        Process.kill(:KILL, @test_pid) if @test_pid
      ensure
        @test_out.close if @test_out
      end
    end

    #def test_childs
    #end
    
    def test_should_run_all_without_any_leaks
      spawn_runner
      buf = timeout(10){@test_out.read}
      assert_match(/^\.+SF\.+F\.*$/,buf)
    end

    def test_should_retry_failed_on_workers
      spawn_runner
      buf = timeout(10){@test_out.read}
      assert_match(/^Retrying\.+$/,buf)
      assert_match(/^\.*SF\.*$/,buf)
    end

    def test_no_retry_option
      spawn_runner "--no-retry"
      buf = timeout(10){@test_out.read}
      refute_match(/^Retrying\.+$/,buf)
      assert_match(/^ +\d+\) Failure:\nptest_fail_at_worker\(TestD\)/,buf)
    end

    def test_jobs_status
      spawn_runner "--jobs-status"
      buf = timeout(10){@test_out.read}
      assert_match(/\d+:(ready|prepare|running) */,buf)
      assert_match(/test_(first|second|third|forth) */,buf)
    end

  end
end
