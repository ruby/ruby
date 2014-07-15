require File.expand_path('../helper', __FILE__)

class TestRakeApplication < Rake::TestCase

  def setup
    super

    @app = Rake.application
    @app.options.rakelib = []
  end

  def setup_command_line(*options)
    ARGV.clear
    options.each do |option|
      ARGV << option
    end
  end

  def test_display_exception_details
    begin
      raise 'test'
    rescue => ex
    end

    out, err = capture_io do
      @app.display_error_message ex
    end

    assert_empty out

    assert_match 'rake aborted!', err
    assert_match __method__.to_s, err
  end

  def test_display_exception_details_cause
    skip 'Exception#cause not implemented' unless
      Exception.method_defined? :cause

    begin
      raise 'cause a'
    rescue
      begin
        raise 'cause b'
      rescue => ex
      end
    end

    out, err = capture_io do
      @app.display_error_message ex
    end

    assert_empty out

    assert_match 'cause a', err
    assert_match 'cause b', err
  end

  def test_display_exception_details_cause_loop
    skip 'Exception#cause not implemented' unless
      Exception.method_defined? :cause

    begin
      begin
        raise 'cause a'
      rescue => a
        begin
          raise 'cause b'
        rescue
          raise a
        end
      end
    rescue => ex
    end

    out, err = capture_io do
      @app.display_error_message ex
    end

    assert_empty out

    assert_match 'cause a', err
    assert_match 'cause b', err
  end

  def test_display_tasks
    @app.options.show_tasks = :tasks
    @app.options.show_task_pattern = //
    @app.last_description = "COMMENT"
    @app.define_task(Rake::Task, "t")
    out, = capture_io do @app.instance_eval { display_tasks_and_comments } end
    assert_match(/^rake t/, out)
    assert_match(/# COMMENT/, out)
  end

  def test_display_tasks_with_long_comments
    @app.terminal_columns = 80
    @app.options.show_tasks = :tasks
    @app.options.show_task_pattern = //
    numbers = "1234567890" * 8
    @app.last_description = numbers
    @app.define_task(Rake::Task, "t")

    out, = capture_io do @app.instance_eval { display_tasks_and_comments } end

    assert_match(/^rake t/, out)
    assert_match(/# #{numbers[0, 65]}\.\.\./, out)
  end

  def test_display_tasks_with_task_name_wider_than_tty_display
    @app.terminal_columns = 80
    @app.options.show_tasks = :tasks
    @app.options.show_task_pattern = //
    task_name = "task name" * 80
    @app.last_description = "something short"
    @app.define_task(Rake::Task, task_name)

    out, = capture_io do @app.instance_eval { display_tasks_and_comments } end

    # Ensure the entire task name is output and we end up showing no description
    assert_match(/rake #{task_name}  # .../, out)
  end

  def test_display_tasks_with_very_long_task_name_to_a_non_tty_shows_name_and_comment
    @app.options.show_tasks = :tasks
    @app.options.show_task_pattern = //
    @app.tty_output = false
    description = "something short"
    task_name = "task name" * 80
    @app.last_description = "something short"
    @app.define_task(Rake::Task, task_name)

    out, = capture_io do @app.instance_eval { display_tasks_and_comments } end

    # Ensure the entire task name is output and we end up showing no description
    assert_match(/rake #{task_name}  # #{description}/, out)
  end

  def test_display_tasks_with_long_comments_to_a_non_tty_shows_entire_comment
    @app.options.show_tasks = :tasks
    @app.options.show_task_pattern = //
    @app.tty_output = false
    @app.last_description = "1234567890" * 8
    @app.define_task(Rake::Task, "t")
    out, = capture_io do @app.instance_eval { display_tasks_and_comments } end
    assert_match(/^rake t/, out)
    assert_match(/# #{@app.last_description}/, out)
  end

  def test_truncating_comments_to_a_non_tty
    @app.terminal_columns = 80
    @app.options.show_tasks = :tasks
    @app.options.show_task_pattern = //
    @app.tty_output = false
    numbers = "1234567890" * 8
    @app.last_description = numbers
    @app.define_task(Rake::Task, "t")

    out, = capture_io do @app.instance_eval { display_tasks_and_comments } end

    assert_match(/^rake t/, out)
    assert_match(/# #{numbers[0, 65]}\.\.\./, out)
  end

  def test_describe_tasks
    @app.options.show_tasks = :describe
    @app.options.show_task_pattern = //
    @app.last_description = "COMMENT"
    @app.define_task(Rake::Task, "t")
    out, = capture_io do @app.instance_eval { display_tasks_and_comments } end
    assert_match(/^rake t$/, out)
    assert_match(/^ {4}COMMENT$/, out)
  end

  def test_show_lines
    @app.options.show_tasks = :lines
    @app.options.show_task_pattern = //
    @app.last_description = "COMMENT"
    @app.define_task(Rake::Task, "t")
    @app['t'].locations << "HERE:1"
    out, = capture_io do @app.instance_eval { display_tasks_and_comments } end
    assert_match(/^rake t +[^:]+:\d+ *$/, out)
  end

  def test_finding_rakefile
    rakefile_default

    assert_match(/Rakefile/i, @app.instance_eval { have_rakefile })
  end

  def test_not_finding_rakefile
    @app.instance_eval { @rakefiles = ['NEVER_FOUND'] }
    assert(! @app.instance_eval do have_rakefile end)
    assert_nil @app.rakefile
  end

  def test_load_rakefile
    rakefile_unittest

    @app.instance_eval do
      handle_options
      options.silent = true
      load_rakefile
    end

    assert_equal "rakefile", @app.rakefile.downcase
    assert_equal @tempdir, Dir.pwd
  end

  def test_load_rakefile_doesnt_print_rakefile_directory_from_same_dir
    rakefile_unittest

    _, err = capture_io do
      @app.instance_eval do
        # pretend we started from the unittest dir
        @original_dir = File.expand_path(".")
        raw_load_rakefile
      end
    end

    assert_empty err
  end

  def test_load_rakefile_from_subdir
    rakefile_unittest
    Dir.chdir 'subdir'

    @app.instance_eval do
      handle_options
      options.silent = true
      load_rakefile
    end

    assert_equal "rakefile", @app.rakefile.downcase
    assert_equal @tempdir, Dir.pwd
  end

  def test_load_rakefile_prints_rakefile_directory_from_subdir
    rakefile_unittest
    Dir.chdir 'subdir'

    app = Rake::Application.new
    app.options.rakelib = []

    _, err = capture_io do
      app.instance_eval do
        raw_load_rakefile
      end
    end

    assert_equal "(in #{@tempdir}\)\n", err
  end

  def test_load_rakefile_doesnt_print_rakefile_directory_from_subdir_if_silent
    rakefile_unittest
    Dir.chdir 'subdir'

    _, err = capture_io do
      @app.instance_eval do
        handle_options
        options.silent = true
        raw_load_rakefile
      end
    end

    assert_empty err
  end

  def test_load_rakefile_not_found
    ARGV.clear
    Dir.chdir @tempdir
    ENV['RAKE_SYSTEM'] = 'not_exist'

    @app.instance_eval do
      handle_options
      options.silent = true
    end


    ex = assert_raises(RuntimeError) do
      @app.instance_eval do
        raw_load_rakefile
      end
    end

    assert_match(/no rakefile found/i, ex.message)
  end

  def test_load_from_system_rakefile
    rake_system_dir

    @app.instance_eval do
      handle_options
      options.silent = true
      options.load_system = true
      options.rakelib = []
      load_rakefile
    end

    assert_equal @system_dir, @app.system_dir
    assert_nil @app.rakefile
  rescue SystemExit
    flunk 'failed to load rakefile'
  end

  def test_load_from_calculated_system_rakefile
    rakefile_default
    def @app.standard_system_dir
      "__STD_SYS_DIR__"
    end

    ENV['RAKE_SYSTEM'] = nil

    @app.instance_eval do
      handle_options
      options.silent = true
      options.load_system = true
      options.rakelib = []
      load_rakefile
    end

    assert_equal "__STD_SYS_DIR__", @app.system_dir
  rescue SystemExit
    flunk 'failed to find system rakefile'
  end

  def test_terminal_columns
    old_rake_columns = ENV['RAKE_COLUMNS']

    ENV['RAKE_COLUMNS'] = '42'

    app = Rake::Application.new

    assert_equal 42, app.terminal_columns
  ensure
    if old_rake_columns
      ENV['RAKE_COLUMNS'].delete
    else
      ENV['RAKE_COLUMNS'] = old_rake_columns
    end
  end

  def test_windows
    assert ! (@app.windows? && @app.unix?)
  end

  def test_loading_imports
    loader = util_loader

    @app.instance_eval do
      add_loader("dummy", loader)
      add_import("x.dummy")
      load_imports
    end

    # HACK no assertions
  end

  def test_building_imported_files_on_demand
    loader = util_loader

    @app.instance_eval do
      intern(Rake::Task, "x.dummy").enhance do loader.make_dummy end
      add_loader("dummy", loader)
      add_import("x.dummy")
      load_imports
    end

    # HACK no assertions
  end

  def test_handle_options_should_strip_options_from_argv
    assert !@app.options.trace

    valid_option = '--trace'
    setup_command_line(valid_option)

    @app.handle_options

    assert !ARGV.include?(valid_option)
    assert @app.options.trace
  end

  def test_handle_options_trace_default_is_stderr
    setup_command_line("--trace")

    @app.handle_options

    assert_equal STDERR, @app.options.trace_output
    assert @app.options.trace
  end

  def test_handle_options_trace_overrides_to_stdout
    setup_command_line("--trace=stdout")

    @app.handle_options

    assert_equal STDOUT, @app.options.trace_output
    assert @app.options.trace
  end

  def test_handle_options_trace_does_not_eat_following_task_names
    assert !@app.options.trace

    setup_command_line("--trace", "sometask")

    @app.handle_options
    assert ARGV.include?("sometask")
    assert @app.options.trace
  end

  def test_good_run
    ran = false

    ARGV << '--rakelib=""'

    @app.options.silent = true

    @app.instance_eval do
      intern(Rake::Task, "default").enhance { ran = true }
    end

    rakefile_default

    out, err = capture_io do
      @app.run
    end

    assert ran
    assert_empty err
    assert_equal "DEFAULT\n", out
  end

  def test_display_task_run
    ran = false
    setup_command_line('-f', '-s', '--tasks', '--rakelib=""')
    @app.last_description = "COMMENT"
    @app.define_task(Rake::Task, "default")
    out, = capture_io { @app.run }
    assert @app.options.show_tasks
    assert ! ran
    assert_match(/rake default/, out)
    assert_match(/# COMMENT/, out)
  end

  def test_display_prereqs
    ran = false
    setup_command_line('-f', '-s', '--prereqs', '--rakelib=""')
    @app.last_description = "COMMENT"
    t = @app.define_task(Rake::Task, "default")
    t.enhance([:a, :b])
    @app.define_task(Rake::Task, "a")
    @app.define_task(Rake::Task, "b")
    out, = capture_io { @app.run }
    assert @app.options.show_prereqs
    assert ! ran
    assert_match(/rake a$/, out)
    assert_match(/rake b$/, out)
    assert_match(/rake default\n( *(a|b)\n){2}/m, out)
  end

  def test_bad_run
    @app.intern(Rake::Task, "default").enhance { fail }
    setup_command_line('-f', '-s',  '--rakelib=""')
    _, err = capture_io {
      assert_raises(SystemExit){ @app.run }
    }
    assert_match(/see full trace/i, err)
  ensure
    ARGV.clear
  end

  def test_bad_run_with_trace
    @app.intern(Rake::Task, "default").enhance { fail }
    setup_command_line('-f', '-s', '-t')
    _, err = capture_io {
      assert_raises(SystemExit) { @app.run }
    }
    refute_match(/see full trace/i, err)
  ensure
    ARGV.clear
  end

  def test_bad_run_with_backtrace
    @app.intern(Rake::Task, "default").enhance { fail }
    setup_command_line('-f', '-s', '--backtrace')
    _, err = capture_io {
      assert_raises(SystemExit) {
        @app.run
      }
    }
    refute_match(/see full trace/, err)
  ensure
    ARGV.clear
  end

  CustomError = Class.new(RuntimeError)

  def test_bad_run_includes_exception_name
    @app.intern(Rake::Task, "default").enhance {
        raise CustomError, "intentional"
    }
    setup_command_line('-f', '-s')
    _, err = capture_io {
      assert_raises(SystemExit) {
        @app.run
      }
    }
    assert_match(/CustomError: intentional/, err)
  end

  def test_rake_error_excludes_exception_name
    @app.intern(Rake::Task, "default").enhance {
      fail "intentional"
    }
    setup_command_line('-f', '-s')
    _, err = capture_io {
      assert_raises(SystemExit) {
        @app.run
      }
   }
   refute_match(/RuntimeError/, err)
   assert_match(/intentional/, err)
  end

  def cause_supported?
    ex = StandardError.new
    ex.respond_to?(:cause)
  end

  def test_printing_original_exception_cause
    custom_error = Class.new(StandardError)
    @app.intern(Rake::Task, "default").enhance {
      begin
        raise custom_error, "Original Error"
      rescue custom_error
        raise custom_error, "Secondary Error"
      end
    }
    setup_command_line('-f', '-s')
    _ ,err = capture_io {
      assert_raises(SystemExit) {
        @app.run
      }
    }
    if cause_supported?
      assert_match(/Original Error/, err)
    end
    assert_match(/Secondary Error/, err)
  ensure
    ARGV.clear
  end

  def test_run_with_bad_options
    @app.intern(Rake::Task, "default").enhance { fail }
    setup_command_line('-f', '-s', '--xyzzy')
    assert_raises(SystemExit) {
      capture_io { @app.run }
    }
  ensure
    ARGV.clear
  end

  def test_standard_exception_handling_invalid_option
    out, err = capture_io do
      e = assert_raises SystemExit do
        @app.standard_exception_handling do
          raise OptionParser::InvalidOption, 'blah'
        end
      end

      assert_equal 1, e.status
    end

    assert_empty out
    assert_equal "invalid option: blah\n", err
  end

  def test_standard_exception_handling_other
    out, err = capture_io do
      e = assert_raises SystemExit do
        @app.standard_exception_handling do
          raise 'blah'
        end
      end

      assert_equal 1, e.status
    end

    assert_empty out
    assert_match "rake aborted!\n", err
    assert_match "blah\n", err
  end

  def test_standard_exception_handling_system_exit
    out, err = capture_io do
      e = assert_raises SystemExit do
        @app.standard_exception_handling do
          exit 0
        end
      end

      assert_equal 0, e.status
    end

    assert_empty out
    assert_empty err
  end

  def test_standard_exception_handling_system_exit_nonzero
    out, err = capture_io do
      e = assert_raises SystemExit do
        @app.standard_exception_handling do
          exit 5
        end
      end

      assert_equal 5, e.status
    end

    assert_empty out
    assert_empty err
  end

  def util_loader
    loader = Object.new

    loader.instance_variable_set :@load_called, false
    def loader.load arg
      raise ArgumentError, arg unless arg == 'x.dummy'
      @load_called = true
    end

    loader.instance_variable_set :@make_dummy_called, false
    def loader.make_dummy
      @make_dummy_called = true
    end

    loader
  end

end
