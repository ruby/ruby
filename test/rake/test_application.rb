require 'test/unit'
require 'rake'
require_relative 'capture_stdout'
require_relative 'in_environment'

TESTING_REQUIRE = [ ]

######################################################################
class Rake::TestApplication < Test::Unit::TestCase
  include CaptureStdout
  include InEnvironment
  BASEDIR = File.dirname(__FILE__)

  def defmock(*names, &block)
    class << (@mock ||= Object.new); self; end.class_eval do
      names.each do |name|
        define_method(name, block)
      end
    end
    @mock
  end

  def setup
    @app = Rake::Application.new
    @app.options.rakelib = []
  end

  def test_constant_warning
    err = capture_stderr do @app.instance_eval { const_warning("Task") } end
    assert_match(/warning/i, err)
    assert_match(/deprecated/i, err)
    assert_match(/Task/i, err)
  end

  def test_display_tasks
    @app.options.show_task_pattern = //
    @app.last_description = "COMMENT"
    @app.define_task(Rake::Task, "t")
    out = capture_stdout do @app.instance_eval { display_tasks_and_comments } end
    assert_match(/^rake t/, out)
    assert_match(/# COMMENT/, out)
  end

  def test_display_tasks_with_long_comments
    in_environment('RAKE_COLUMNS' => '80') do
      @app.options.show_task_pattern = //
      @app.last_description = "1234567890" * 8
      @app.define_task(Rake::Task, "t")
      out = capture_stdout do @app.instance_eval { display_tasks_and_comments } end
      assert_match(/^rake t/, out)
      assert_match(/# 12345678901234567890123456789012345678901234567890123456789012345\.\.\./, out)
    end
  end

  def test_display_tasks_with_task_name_wider_than_tty_display
    in_environment('RAKE_COLUMNS' => '80') do
      @app.options.show_task_pattern = //
      description = "something short"
      task_name = "task name" * 80
      @app.last_description = "something short"
      @app.define_task(Rake::Task, task_name )
      out = capture_stdout do @app.instance_eval { display_tasks_and_comments } end
      # Ensure the entire task name is output and we end up showing no description
      assert_match(/rake #{task_name}  # .../, out)
    end
  end

  def test_display_tasks_with_very_long_task_name_to_a_non_tty_shows_name_and_comment
    @app.options.show_task_pattern = //
    @app.tty_output = false
    description = "something short"
    task_name = "task name" * 80
    @app.last_description = "something short"
    @app.define_task(Rake::Task, task_name )
    out = capture_stdout do @app.instance_eval { display_tasks_and_comments } end
    # Ensure the entire task name is output and we end up showing no description
    assert_match(/rake #{task_name}  # #{description}/, out)
  end

  def test_display_tasks_with_long_comments_to_a_non_tty_shows_entire_comment
    @app.options.show_task_pattern = //
    @app.tty_output = false
    @app.last_description = "1234567890" * 8
    @app.define_task(Rake::Task, "t")
    out = capture_stdout do @app.instance_eval { display_tasks_and_comments } end
    assert_match(/^rake t/, out)
    assert_match(/# #{@app.last_description}/, out)
  end

  def test_display_tasks_with_long_comments_to_a_non_tty_with_columns_set_truncates_comments
    in_environment("RAKE_COLUMNS" => '80') do
      @app.options.show_task_pattern = //
      @app.tty_output = false
      @app.last_description = "1234567890" * 8
      @app.define_task(Rake::Task, "t")
      out = capture_stdout do @app.instance_eval { display_tasks_and_comments } end
      assert_match(/^rake t/, out)
      assert_match(/# 12345678901234567890123456789012345678901234567890123456789012345\.\.\./, out)
    end
  end

  def test_display_tasks_with_full_descriptions
    @app.options.show_task_pattern = //
    @app.options.full_description = true
    @app.last_description = "COMMENT"
    @app.define_task(Rake::Task, "t")
    out = capture_stdout do @app.instance_eval { display_tasks_and_comments } end
    assert_match(/^rake t$/, out)
    assert_match(/^ {4}COMMENT$/, out)
  end

  def test_finding_rakefile
    in_environment("PWD" => File.join(BASEDIR, "data/unittest")) do
      assert_match(/Rakefile/i, @app.instance_eval { have_rakefile })
    end
  end

  def test_not_finding_rakefile
    @app.instance_eval { @rakefiles = ['NEVER_FOUND'] }
    assert( ! @app.instance_eval do have_rakefile end )
    assert_nil @app.rakefile
  end

  def test_load_rakefile
    in_environment("PWD" => File.join(BASEDIR, "data/unittest")) do
      @app.instance_eval do 
        handle_options
        options.silent = true
        load_rakefile
      end
      assert_equal "rakefile", @app.rakefile.downcase
      assert_match(%r(unittest$), Dir.pwd)
    end
  end

  def test_load_rakefile_from_subdir
    in_environment("PWD" => File.join(BASEDIR, "data/unittest/subdir")) do
      @app.instance_eval do
        handle_options
        options.silent = true
        load_rakefile
      end
      assert_equal "rakefile", @app.rakefile.downcase
      assert_match(%r(unittest$), Dir.pwd)
    end
  end

  def test_load_rakefile_not_found
    in_environment("PWD" => "/", "RAKE_SYSTEM" => 'not_exist') do
      @app.instance_eval do
        handle_options
        options.silent = true
      end
      ex = assert_raise(RuntimeError) do 
        @app.instance_eval do raw_load_rakefile end 
      end
      assert_match(/no rakefile found/i, ex.message)
    end
  end

  def test_load_from_system_rakefile
    system_dir = File.expand_path('../data/default', __FILE__)
    in_environment('RAKE_SYSTEM' => system_dir) do
      @app.options.rakelib = []
      @app.instance_eval do
        handle_options
        options.silent = true
        options.load_system = true
        options.rakelib = []
        load_rakefile
      end
      assert_equal system_dir, @app.system_dir
      assert_nil @app.rakefile
    end
  end

  def test_windows
    assert ! (@app.windows? && @app.unix?)
  end

  def test_loading_imports
    args = []
    mock = defmock(:load) {|*a| args << a}
    @app.instance_eval do
      add_loader("dummy", mock)
      add_import("x.dummy")
      load_imports
    end
    assert_equal([["x.dummy"]], args)
  end

  def test_building_imported_files_on_demand
    args = []
    callback = false
    mock = defmock(:load) {|*a| args << a}
    @app.instance_eval do
      intern(Rake::Task, "x.dummy").enhance do callback = true end
        add_loader("dummy", mock)
      add_import("x.dummy")
      load_imports
    end
    assert_equal([["x.dummy"]], args)
    assert(callback)
  end

  def test_handle_options_should_strip_options_from_ARGV
    assert !@app.options.trace

    valid_option = '--trace'
    ARGV.clear
    ARGV << valid_option

    @app.handle_options

    assert !ARGV.include?(valid_option)
    assert @app.options.trace
  end

  def test_good_run
    ran = false
    ARGV.clear
    ARGV << '--rakelib=""'
    @app.options.silent = true
    @app.instance_eval do
      intern(Rake::Task, "default").enhance { ran = true }
    end
    in_environment("PWD" => File.join(BASEDIR, "data/default")) do
      @app.run
    end
    assert ran
  end

  def test_display_task_run
    ran = false
    ARGV.clear
    ARGV << '-f' << '-s' << '--tasks' << '--rakelib=""'
    @app.last_description = "COMMENT"
    @app.define_task(Rake::Task, "default")
    out = capture_stdout { @app.run }
    assert @app.options.show_tasks
    assert ! ran
    assert_match(/rake default/, out)
    assert_match(/# COMMENT/, out)
  end

  def test_display_prereqs
    ran = false
    ARGV.clear
    ARGV << '-f' << '-s' << '--prereqs' << '--rakelib=""'
    @app.last_description = "COMMENT"
    t = @app.define_task(Rake::Task, "default")
    t.enhance([:a, :b])
    @app.define_task(Rake::Task, "a")
    @app.define_task(Rake::Task, "b")
    out = capture_stdout { @app.run }
    assert @app.options.show_prereqs
    assert ! ran
    assert_match(/rake a$/, out)
    assert_match(/rake b$/, out)
    assert_match(/rake default\n( *(a|b)\n){2}/m, out)
  end

  def test_bad_run
    @app.intern(Rake::Task, "default").enhance { fail }
    ARGV.clear
    ARGV << '-f' << '-s' <<  '--rakelib=""'
    assert_raise(SystemExit) {
      err = capture_stderr { @app.run }
      assert_match(/see full trace/, err)
    }
  ensure
    ARGV.clear
  end

  def test_bad_run_with_trace
    @app.intern(Rake::Task, "default").enhance { fail }
    ARGV.clear
    ARGV << '-f' << '-s' << '-t'
    assert_raise(SystemExit) {
      err = capture_stderr { capture_stdout { @app.run } }
      assert_no_match(/see full trace/, err)
    }
  ensure
    ARGV.clear
  end

  def test_run_with_bad_options
    @app.intern(Rake::Task, "default").enhance { fail }
    ARGV.clear
    ARGV << '-f' << '-s' << '--xyzzy'
    assert_raise(SystemExit) {
      err = capture_stderr { capture_stdout { @app.run } }
    }
  ensure
    ARGV.clear
  end
end


######################################################################
class Rake::TestApplicationOptions < Test::Unit::TestCase
  include CaptureStdout

  def setup
    clear_argv
    RakeFileUtils.verbose_flag = false
    RakeFileUtils.nowrite_flag = false
    TESTING_REQUIRE.clear
  end

  def teardown
    clear_argv
    RakeFileUtils.verbose_flag = false
    RakeFileUtils.nowrite_flag = false
  end
  
  def clear_argv
    while ! ARGV.empty?
      ARGV.pop
    end
  end

  def test_default_options
    opts = command_line
    assert_nil opts.classic_namespace
    assert_nil opts.dryrun
    assert_nil opts.full_description
    assert_nil opts.ignore_system
    assert_nil opts.load_system
    assert_nil opts.nosearch
    assert_equal ['rakelib'], opts.rakelib
    assert_nil opts.show_prereqs
    assert_nil opts.show_task_pattern
    assert_nil opts.show_tasks
    assert_nil opts.silent
    assert_nil opts.trace
    assert_equal ['rakelib'], opts.rakelib
    assert ! RakeFileUtils.verbose_flag
    assert ! RakeFileUtils.nowrite_flag
  end

  def test_dry_run
    flags('--dry-run', '-n') do |opts|
      assert opts.dryrun
      assert opts.trace
      assert RakeFileUtils.verbose_flag
      assert RakeFileUtils.nowrite_flag
    end
  end

  def test_describe
    flags('--describe') do |opts|
      assert opts.full_description
      assert opts.show_tasks
      assert_equal(//.to_s, opts.show_task_pattern.to_s)
    end
  end

  def test_describe_with_pattern
    flags('--describe=X') do |opts|
      assert opts.full_description
      assert opts.show_tasks
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
      assert_not_equal :exit, @exit
      $xyzzy = 0
    end
  end

  def test_execute_and_print
    $xyzzy = 0
    flags('--execute-print=$xyzzy="pugh"', '-p $xyzzy="pugh"') do |opts|
      assert_equal 'pugh', $xyzzy
      assert_equal :exit, @exit
      assert_match(/^pugh$/, @out)
      $xyzzy = 0
    end
  end

  def test_help
    flags('--help', '-H', '-h') do |opts|
      assert_match(/\Arake/, @out)
      assert_match(/\boptions\b/, @out)
      assert_match(/\btargets\b/, @out)
      assert_equal :exit, @exit
      assert_equal :exit, @exit
    end
  end

  def test_libdir
    flags(['--libdir', 'xx'], ['-I', 'xx'], ['-Ixx']) do |opts|
      $:.include?('xx')
    end
  ensure
    $:.delete('xx')
  end

  def test_rakefile
    flags(['--rakefile', 'RF'], ['--rakefile=RF'], ['-f', 'RF'], ['-fRF']) do |opts|
      assert_equal ['RF'], @app.instance_eval { @rakefiles }
    end
  end

  def test_rakelib
    flags(['--rakelibdir', 'A:B:C'], ['--rakelibdir=A:B:C'], ['-R', 'A:B:C'], ['-RA:B:C']) do |opts|
      assert_equal ['A', 'B', 'C'], opts.rakelib
    end
  end

  def test_require
    flags(['--require', File.expand_path('../reqfile', __FILE__)],
          "-r#{File.expand_path('../reqfile2', __FILE__)}",
          "-r#{File.expand_path('../reqfile3', __FILE__)}") do |opts|
    end
    assert TESTING_REQUIRE.include?(1)
    assert TESTING_REQUIRE.include?(2)
    assert TESTING_REQUIRE.include?(3)
    assert_equal 3, TESTING_REQUIRE.size
  end

  def test_missing_require
    ex = assert_raise(LoadError) do
      flags(['--require', File.expand_path('../missing', __FILE__)]) do |opts|
      end
    end
    assert_match(/cannot load such file/, ex.message)
    assert_match(/#{File.basename(File.dirname(__FILE__))}\/missing/, ex.message)
  end

  def test_prereqs
    flags('--prereqs', '-P') do |opts|
      assert opts.show_prereqs
    end
  end

  def test_quiet
    flags('--quiet', '-q') do |opts|
      assert ! RakeFileUtils.verbose_flag
      assert ! opts.silent
    end
  end

  def test_no_search
    flags('--nosearch', '--no-search', '-N') do |opts|
      assert opts.nosearch
    end
  end

  def test_silent
    flags('--silent', '-s') do |opts|
      assert ! RakeFileUtils.verbose_flag
      assert opts.silent
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
      assert opts.trace
      assert RakeFileUtils.verbose_flag
      assert ! RakeFileUtils.nowrite_flag
    end
  end

  def test_trace_rules
    flags('--rules') do |opts|
      assert opts.trace_rules
    end
  end

  def test_tasks
    flags('--tasks', '-T') do |opts|
      assert opts.show_tasks
      assert_equal(//.to_s, opts.show_task_pattern.to_s)
    end
    flags(['--tasks', 'xyz'], ['-Txyz']) do |opts|
      assert opts.show_tasks
      assert_equal(/xyz/, opts.show_task_pattern)
    end
  end

  def test_verbose
    flags('--verbose', '-V') do |opts|
      assert RakeFileUtils.verbose_flag
      assert ! opts.silent
    end
  end

  def test_version
    flags('--version', '-V') do |opts|
      assert_match(/\bversion\b/, @out)
      assert_match(/\b#{RAKEVERSION}\b/, @out)
      assert_equal :exit, @exit
    end
  end
  
  def test_classic_namespace
    flags(['--classic-namespace'], ['-C', '-T', '-P', '-n', '-s', '-t']) do |opts|
      assert opts.classic_namespace
      assert_equal opts.show_tasks, $show_tasks
      assert_equal opts.show_prereqs, $show_prereqs
      assert_equal opts.trace, $trace
      assert_equal opts.dryrun, $dryrun
      assert_equal opts.silent, $silent
    end
  end

  def test_bad_option
    capture_stderr do
      ex = assert_raise(OptionParser::InvalidOption) do
        flags('--bad-option') 
      end
      if ex.message =~ /^While/ # Ruby 1.9 error message
        assert_match(/while parsing/i, ex.message)
      else                      # Ruby 1.8 error message
        assert_match(/(invalid|unrecognized) option/i, ex.message)
        assert_match(/--bad-option/, ex.message)
      end
    end
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
    command_line("a", "TESTKEY=12")
    assert_equal ["a"], @tasks.sort
    assert '12', ENV['TESTKEY']
  end

  private 

  def flags(*sets)
    sets.each do |set|
      ARGV.clear
      @out = capture_stdout { 
        @exit = catch(:system_exit) { opts = command_line(*set) }
      }
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
      handle_options
      collect_tasks
    end
    @tasks = @app.top_level_tasks
    @app.options
  end
end

class Rake::TestTaskArgumentParsing < Test::Unit::TestCase
  def setup
    @app = Rake::Application.new
  end
  
  def test_name_only
    name, args = @app.parse_task_string("name")
    assert_equal "name", name
    assert_equal [], args
  end
  
  def test_empty_args
    name, args = @app.parse_task_string("name[]")
    assert_equal "name", name
    assert_equal [], args
  end
  
  def test_one_argument
    name, args = @app.parse_task_string("name[one]")
    assert_equal "name", name
    assert_equal ["one"], args
  end
  
  def test_two_arguments
    name, args = @app.parse_task_string("name[one,two]")
    assert_equal "name", name
    assert_equal ["one", "two"], args
  end
  
  def test_can_handle_spaces_between_args
    name, args = @app.parse_task_string("name[one, two,\tthree , \tfour]")
    assert_equal "name", name
    assert_equal ["one", "two", "three", "four"], args
  end

  def test_keeps_embedded_spaces
    name, args = @app.parse_task_string("name[a one ana, two]")
    assert_equal "name", name
    assert_equal ["a one ana", "two"], args
  end

end

class Rake::TestTaskArgumentParsing < Test::Unit::TestCase
  include InEnvironment

  def test_terminal_width_using_env
    app = Rake::Application.new
    in_environment('RAKE_COLUMNS' => '1234') do
      assert_equal 1234, app.terminal_width
    end
  end

  def test_terminal_width_using_stty
    app = Rake::Application.new
    def app.unix?() true end
    def app.dynamic_width_stty() 1235 end
    def app.dynamic_width_tput() 0 end
    in_environment('RAKE_COLUMNS' => nil) do
      assert_equal 1235, app.terminal_width
    end
  end

  def test_terminal_width_using_tput
    app = Rake::Application.new
    def app.unix?() true end
    def app.dynamic_width_stty() 0 end
    def app.dynamic_width_tput() 1236 end
    in_environment('RAKE_COLUMNS' => nil) do
      assert_equal 1236, app.terminal_width
    end
  end

  def test_terminal_width_using_hardcoded_80
    app = Rake::Application.new
    def app.unix?() false end
    in_environment('RAKE_COLUMNS' => nil) do
      assert_equal 80, app.terminal_width
    end
  end

  def test_terminal_width_with_failure
    app = Rake::Application.new
    called = false
    class << app; self; end.class_eval do
      define_method(:unix?) {|*a|
        called = a
        raise RuntimeError
      }
    end
    in_environment('RAKE_COLUMNS' => nil) do
      assert_equal 80, app.terminal_width
    end
    assert_equal([], called)
  end
end
