require File.expand_path('../helper', __FILE__)

TESTING_REQUIRE = []

class TestRakeApplicationOptions < Rake::TestCase

  def setup
    super

    clear_argv
    Rake::FileUtilsExt.verbose_flag = false
    Rake::FileUtilsExt.nowrite_flag = false
    TESTING_REQUIRE.clear
  end

  def teardown
    clear_argv
    Rake::FileUtilsExt.verbose_flag = false
    Rake::FileUtilsExt.nowrite_flag = false

    super
  end

  def clear_argv
    ARGV.pop until ARGV.empty?
  end

  def test_default_options
    opts = command_line
    assert_nil opts.backtrace
    assert_nil opts.dryrun
    assert_nil opts.ignore_system
    assert_nil opts.load_system
    assert_nil opts.always_multitask
    assert_nil opts.nosearch
    assert_equal ['rakelib'], opts.rakelib
    assert_nil opts.show_prereqs
    assert_nil opts.show_task_pattern
    assert_nil opts.show_tasks
    assert_nil opts.silent
    assert_nil opts.trace
    assert_nil opts.thread_pool_size
    assert_equal ['rakelib'], opts.rakelib
    assert ! Rake::FileUtilsExt.verbose_flag
    assert ! Rake::FileUtilsExt.nowrite_flag
  end

  def test_dry_run
    flags('--dry-run', '-n') do |opts|
      assert opts.dryrun
      assert opts.trace
      assert Rake::FileUtilsExt.verbose_flag
      assert Rake::FileUtilsExt.nowrite_flag
    end
  end

  def test_describe
    flags('--describe') do |opts|
      assert_equal :describe, opts.show_tasks
      assert_equal(//.to_s, opts.show_task_pattern.to_s)
    end
  end

  def test_describe_with_pattern
    flags('--describe=X') do |opts|
      assert_equal :describe, opts.show_tasks
      assert_equal(/X/.to_s, opts.show_task_pattern.to_s)
    end
  end

  def test_execute
    $xyzzy = 0
    flags('--execute=$xyzzy=1', '-e $xyzzy=1') do |opts|
      assert_equal 1, $xyzzy
      assert_equal :exit, @exit
      $xyzzy = 0
    end
  end

  def test_execute_and_continue
    $xyzzy = 0
    flags('--execute-continue=$xyzzy=1', '-E $xyzzy=1') do |opts|
      assert_equal 1, $xyzzy
      refute_equal :exit, @exit
      $xyzzy = 0
    end
  end

  def test_execute_and_print
    $xyzzy = 0
    out, = capture_io do
      flags('--execute-print=$xyzzy="pugh"', '-p $xyzzy="pugh"') do |opts|
        assert_equal 'pugh', $xyzzy
        assert_equal :exit, @exit
        $xyzzy = 0
      end
    end

    assert_match(/^pugh$/, out)
  end

  def test_help
    out, = capture_io do
      flags '--help', '-H', '-h'
    end

    assert_match(/\Arake/, out)
    assert_match(/\boptions\b/, out)
    assert_match(/\btargets\b/, out)
    assert_equal :exit, @exit
  end

  def test_jobs
    flags([]) do |opts|
      assert_nil opts.thread_pool_size
    end
    flags(['--jobs', '0'], ['-j', '0']) do |opts|
      assert_equal 0, opts.thread_pool_size
    end
    flags(['--jobs', '1'], ['-j', '1']) do |opts|
      assert_equal 0, opts.thread_pool_size
    end
    flags(['--jobs', '4'], ['-j', '4']) do |opts|
      assert_equal 3, opts.thread_pool_size
    end
    flags(['--jobs', 'asdas'], ['-j', 'asdas']) do |opts|
      assert_equal Rake.suggested_thread_count-1, opts.thread_pool_size
    end
    flags('--jobs', '-j') do |opts|
      assert opts.thread_pool_size > 1_000_000, "thread pool size should be huge (was #{opts.thread_pool_size})"
    end
  end

  def test_libdir
    flags(['--libdir', 'xx'], ['-I', 'xx'], ['-Ixx']) do |opts|
      $:.include?('xx')
    end
  ensure
    $:.delete('xx')
  end

  def test_multitask
    flags('--multitask', '-m') do |opts|
      assert_equal opts.always_multitask, true
    end
  end

  def test_rakefile
    flags(['--rakefile', 'RF'], ['--rakefile=RF'], ['-f', 'RF'], ['-fRF']) do |opts|
      assert_equal ['RF'], @app.instance_eval { @rakefiles }
    end
  end

  def test_rakelib
    dirs = %w(A B C).join(File::PATH_SEPARATOR)
    flags(
      ['--rakelibdir', dirs],
      ["--rakelibdir=#{dirs}"],
      ['-R', dirs],
      ["-R#{dirs}"]) do |opts|
      assert_equal ['A', 'B', 'C'], opts.rakelib
    end
  end

  def test_require
    $LOAD_PATH.unshift @tempdir

    open 'reqfile.rb',    'w' do |io| io << 'TESTING_REQUIRE << 1' end
    open 'reqfile2.rb',   'w' do |io| io << 'TESTING_REQUIRE << 2' end
    open 'reqfile3.rake', 'w' do |io| io << 'TESTING_REQUIRE << 3' end

    flags(['--require', 'reqfile'], '-rreqfile2', '-rreqfile3')

    assert_includes TESTING_REQUIRE, 1
    assert_includes TESTING_REQUIRE, 2
    assert_includes TESTING_REQUIRE, 3

    assert_equal 3, TESTING_REQUIRE.size
  ensure
    $LOAD_PATH.delete @tempdir
  end

  def test_missing_require
    ex = assert_raises(LoadError) do
      flags(['--require', 'test/missing']) do |opts|
      end
    end
    assert_match(/such file/, ex.message)
    assert_match(/test\/missing/, ex.message)
  end

  def test_prereqs
    flags('--prereqs', '-P') do |opts|
      assert opts.show_prereqs
    end
  end

  def test_quiet
    Rake::FileUtilsExt.verbose_flag = true
    flags('--quiet', '-q') do |opts|
      assert ! Rake::FileUtilsExt.verbose_flag, "verbose flag shoud be false"
      assert ! opts.silent, "should not be silent"
    end
  end

  def test_no_search
    flags('--nosearch', '--no-search', '-N') do |opts|
      assert opts.nosearch
    end
  end

  def test_silent
    Rake::FileUtilsExt.verbose_flag = true
    flags('--silent', '-s') do |opts|
      assert ! Rake::FileUtilsExt.verbose_flag, "verbose flag should be false"
      assert opts.silent, "should be silent"
    end
  end

  def test_system
    flags('--system', '-g') do |opts|
      assert opts.load_system
    end
  end

  def test_no_system
    flags('--no-system', '-G') do |opts|
      assert opts.ignore_system
    end
  end

  def test_trace
    flags('--trace', '-t') do |opts|
      assert opts.trace, "should enable trace option"
      assert opts.backtrace, "should enabled backtrace option"
      assert_equal $stderr, opts.trace_output
      assert Rake::FileUtilsExt.verbose_flag
      assert ! Rake::FileUtilsExt.nowrite_flag
    end
  end

  def test_trace_with_stdout
    flags('--trace=stdout', '-tstdout') do |opts|
      assert opts.trace, "should enable trace option"
      assert opts.backtrace, "should enabled backtrace option"
      assert_equal $stdout, opts.trace_output
      assert Rake::FileUtilsExt.verbose_flag
      assert ! Rake::FileUtilsExt.nowrite_flag
    end
  end

  def test_trace_with_stderr
    flags('--trace=stderr', '-tstderr') do |opts|
      assert opts.trace, "should enable trace option"
      assert opts.backtrace, "should enabled backtrace option"
      assert_equal $stderr, opts.trace_output
      assert Rake::FileUtilsExt.verbose_flag
      assert ! Rake::FileUtilsExt.nowrite_flag
    end
  end

  def test_trace_with_error
    ex = assert_raises(Rake::CommandLineOptionError) do
      flags('--trace=xyzzy') do |opts| end
    end
    assert_match(/un(known|recognized).*\btrace\b.*xyzzy/i, ex.message)
  end

  def test_trace_with_following_task_name
    flags(['--trace', 'taskname'], ['-t', 'taskname']) do |opts|
      assert opts.trace, "should enable trace option"
      assert opts.backtrace, "should enabled backtrace option"
      assert_equal $stderr, opts.trace_output
      assert Rake::FileUtilsExt.verbose_flag
      assert_equal ['taskname'], @app.top_level_tasks
    end
  end

  def test_backtrace
    flags('--backtrace') do |opts|
      assert opts.backtrace, "should enable backtrace option"
      assert_equal $stderr, opts.trace_output
      assert ! opts.trace, "should not enable trace option"
    end
  end

  def test_backtrace_with_stdout
    flags('--backtrace=stdout') do |opts|
      assert opts.backtrace, "should enable backtrace option"
      assert_equal $stdout, opts.trace_output
      assert ! opts.trace, "should not enable trace option"
    end
  end

  def test_backtrace_with_stderr
    flags('--backtrace=stderr') do |opts|
      assert opts.backtrace, "should enable backtrace option"
      assert_equal $stderr, opts.trace_output
      assert ! opts.trace, "should not enable trace option"
    end
  end

  def test_backtrace_with_error
    ex = assert_raises(Rake::CommandLineOptionError) do
      flags('--backtrace=xyzzy') do |opts| end
    end
    assert_match(/un(known|recognized).*\bbacktrace\b.*xyzzy/i, ex.message)
  end

  def test_backtrace_with_following_task_name
    flags(['--backtrace', 'taskname']) do |opts|
      assert ! opts.trace, "should enable trace option"
      assert opts.backtrace, "should enabled backtrace option"
      assert_equal $stderr, opts.trace_output
      assert_equal ['taskname'], @app.top_level_tasks
    end
  end

  def test_trace_rules
    flags('--rules') do |opts|
      assert opts.trace_rules
    end
  end

  def test_tasks
    flags('--tasks', '-T') do |opts|
      assert_equal :tasks, opts.show_tasks
      assert_equal(//.to_s, opts.show_task_pattern.to_s)
      assert_equal nil, opts.show_all_tasks
    end
    flags(['--tasks', 'xyz'], ['-Txyz']) do |opts|
      assert_equal :tasks, opts.show_tasks
      assert_equal(/xyz/.to_s, opts.show_task_pattern.to_s)
      assert_equal nil, opts.show_all_tasks
    end
    flags(['--tasks', 'xyz', '--comments']) do |opts|
      assert_equal :tasks, opts.show_tasks
      assert_equal(/xyz/.to_s, opts.show_task_pattern.to_s)
      assert_equal false, opts.show_all_tasks
    end
  end

  def test_where
    flags('--where', '-W') do |opts|
      assert_equal :lines, opts.show_tasks
      assert_equal(//.to_s, opts.show_task_pattern.to_s)
      assert_equal true, opts.show_all_tasks
    end
    flags(['--where', 'xyz'], ['-Wxyz']) do |opts|
      assert_equal :lines, opts.show_tasks
      assert_equal(/xyz/.to_s, opts.show_task_pattern.to_s)
      assert_equal true, opts.show_all_tasks
    end
    flags(['--where', 'xyz', '--comments'], ['-Wxyz', '--comments']) do |opts|
      assert_equal :lines, opts.show_tasks
      assert_equal(/xyz/.to_s, opts.show_task_pattern.to_s)
      assert_equal false, opts.show_all_tasks
    end
  end

  def test_no_deprecated_messages
    flags('--no-deprecation-warnings', '-X') do |opts|
      assert opts.ignore_deprecate
    end
  end

  def test_verbose
    capture_io do
      flags('--verbose', '-v') do |opts|
        assert Rake::FileUtilsExt.verbose_flag, "verbose should be true"
        assert ! opts.silent, "opts should not be silent"
      end
    end
  end

  def test_version
    out, _ = capture_io do
      flags '--version', '-V'
    end

    assert_match(/\bversion\b/, out)
    assert_match(/\b#{RAKEVERSION}\b/, out)
    assert_equal :exit, @exit
  end

  def test_bad_option
    _, err = capture_io do
      ex = assert_raises(OptionParser::InvalidOption) do
        flags('--bad-option')
      end

      if ex.message =~ /^While/ # Ruby 1.9 error message
        assert_match(/while parsing/i, ex.message)
      else                      # Ruby 1.8 error message
        assert_match(/(invalid|unrecognized) option/i, ex.message)
        assert_match(/--bad-option/, ex.message)
      end
    end

    assert_equal '', err
  end

  def test_task_collection
    command_line("a", "b")
    assert_equal ["a", "b"], @tasks.sort
  end

  def test_default_task_collection
    command_line()
    assert_equal ["default"], @tasks
  end

  def test_environment_definition
    ENV.delete('TESTKEY')
    command_line("TESTKEY=12")
    assert_equal '12', ENV['TESTKEY']
  end

  def test_multiline_environment_definition
    ENV.delete('TESTKEY')
    command_line("TESTKEY=a\nb\n")
    assert_equal "a\nb\n", ENV['TESTKEY']
  end

  def test_environment_and_tasks_together
    ENV.delete('TESTKEY')
    command_line("a", "b", "TESTKEY=12")
    assert_equal ["a", "b"], @tasks.sort
    assert_equal '12', ENV['TESTKEY']
  end

  def test_rake_explicit_task_library
    Rake.add_rakelib 'app/task', 'other'

    libs = Rake.application.options.rakelib

    assert libs.include?("app/task")
    assert libs.include?("other")
  end

  private

  def flags(*sets)
    sets.each do |set|
      ARGV.clear

      @exit = catch(:system_exit) { command_line(*set) }

      yield(@app.options) if block_given?
    end
  end

  def command_line(*options)
    options.each do |opt| ARGV << opt end
    @app = Rake::Application.new
    def @app.exit(*args)
      throw :system_exit, :exit
    end
    @app.instance_eval do
      args = handle_options
      collect_command_line_tasks(args)
    end
    @tasks = @app.top_level_tasks
    @app.options
  end
end
