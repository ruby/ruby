begin
  old_verbose = $VERBOSE
  $VERBOSE = nil
  require 'session'
rescue LoadError
  if File::ALT_SEPARATOR
    puts "Unable to run functional tests on MS Windows. Skipping."
  else
    puts "Unable to run functional tests -- please run \"gem install session\""
  end
ensure
  $VERBOSE = old_verbose
end

if defined?(Session)
  if File::ALT_SEPARATOR
    puts "Unable to run functional tests on MS Windows. Skipping."
  end
end

require File.expand_path('../helper', __FILE__)
require 'fileutils'

# Version 2.1.9 of session has a bug where the @debug instance
# variable is not initialized, causing warning messages.  This snippet
# of code fixes that problem.
module Session
  class AbstractSession
    alias old_initialize initialize
    def initialize(*args)
      @debug = nil
      old_initialize(*args)
    end
  end
end if defined? Session

class TestRakeFunctional < Rake::TestCase

  def setup
    @rake_path = File.expand_path("bin/rake")
    lib_path = File.expand_path("lib")
    @ruby_options = ["-I#{lib_path}", "-I."]
    @verbose = ENV['VERBOSE']

    if @verbose
      puts
      puts
      puts '-' * 80
      puts @__name__
      puts '-' * 80
    end

    super
  end

  def test_rake_default
    rakefile_default

    rake

    assert_match(/^DEFAULT$/, @out)
    assert_status
  end

  def test_rake_error_on_bad_task
    rakefile_default

    rake "xyz"

    assert_match(/rake aborted/, @err)
    assert_status(1)
  end

  def test_env_available_at_top_scope
    rakefile_default

    rake "TESTTOPSCOPE=1"

    assert_match(/^TOPSCOPE$/, @out)
    assert_status
  end

  def test_env_available_at_task_scope
    rakefile_default

    rake "TESTTASKSCOPE=1 task_scope"

    assert_match(/^TASKSCOPE$/, @out)
    assert_status
  end

  def test_multi_desc
    ENV['RAKE_COLUMNS'] = '80'
    rakefile_multidesc

    rake "-T"

    assert_match %r{^rake a *# A / A2 *$}, @out
    assert_match %r{^rake b *# B *$}, @out
    refute_match %r{^rake c}, @out
    assert_match %r{^rake d *# x{65}\.\.\.$}, @out
  end

  def test_long_description
    rakefile_multidesc

    rake "--describe"

    assert_match %r{^rake a\n *A / A2 *$}m, @out
    assert_match %r{^rake b\n *B *$}m, @out
    assert_match %r{^rake d\n *x{80}}m, @out
    refute_match %r{^rake c\n}m, @out
  end

  def test_proper_namespace_access
    rakefile_access

    rake

    refute_match %r{^BAD:}, @out
  end

  def test_rbext
    rakefile_rbext

    rake "-N"

    assert_match %r{^OK$}, @out
  end

  def test_system
    rake_system_dir

    rake '-g', "sys1"

    assert_match %r{^SYS1}, @out
  end

  def test_system_excludes_rakelib_files_too
    rake_system_dir

    rake '-g', "sys1", '-T', 'extra'

    refute_match %r{extra:extra}, @out
  end

  def test_by_default_rakelib_files_are_included
    rake_system_dir
    rakefile_extra

    rake '-T', 'extra', '--trace'

    assert_match %r{extra:extra}, @out
  end

  def test_implicit_system
    rake_system_dir
    Dir.chdir @tempdir

    rake "sys1", "--trace"

    assert_match %r{^SYS1}, @out
  end

  def test_no_system
    rake_system_dir
    rakefile_extra

    rake '-G', "sys1"

    assert_match %r{^Don't know how to build task}, @err # emacs wart: '
  end

  def test_nosearch_with_rakefile_uses_local_rakefile
    rakefile_default

    rake "--nosearch"

    assert_match %r{^DEFAULT}, @out
  end

  def test_nosearch_without_rakefile_finds_system
    rakefile_nosearch
    rake_system_dir

    rake "--nosearch", "sys1"

    assert_match %r{^SYS1}, @out
  end

  def test_nosearch_without_rakefile_and_no_system_fails
    rakefile_nosearch
    ENV['RAKE_SYSTEM'] = 'not_exist'

    rake "--nosearch"

    assert_match %r{^No Rakefile found}, @err
  end

  def test_invalid_command_line_options
    rakefile_default

    rake "--bad-options"

    assert_match %r{invalid +option}i, @err
  end

  def test_inline_verbose_default_should_show_command
    rakefile_verbose

    rake "inline_verbose_default"

    assert_match(/ruby -e/, @err)
  end

  def test_inline_verbose_true_should_show_command
    rakefile_verbose

    rake "inline_verbose_true"

    assert_match(/ruby -e/, @err)
  end

  def test_inline_verbose_false_should_not_show_command
    rakefile_verbose

    rake "inline_verbose_false"

    refute_match(/ruby -e/, @err)
  end

  def test_block_verbose_false_should_not_show_command
    rakefile_verbose

    rake "block_verbose_false"

    refute_match(/ruby -e/, @err)
  end

  def test_block_verbose_true_should_show_command
    rakefile_verbose

    rake "block_verbose_true"

    assert_match(/ruby -e/, @err)
  end

  def test_standalone_verbose_true_should_show_command
    rakefile_verbose

    rake "standalone_verbose_true"

    assert_match(/ruby -e/, @err)
  end

  def test_standalone_verbose_false_should_not_show_command
    rakefile_verbose

    rake "standalone_verbose_false"

    refute_match(/ruby -e/, @err)
  end

  def test_dry_run
    rakefile_default

    rake "-n", "other"

    assert_match %r{Execute \(dry run\) default}, @err
    assert_match %r{Execute \(dry run\) other}, @err
    refute_match %r{DEFAULT}, @out
    refute_match %r{OTHER}, @out
  end

  # Test for the trace/dry_run bug found by Brian Chandler
  def test_dry_run_bug
    rakefile_dryrun

    rake

    FileUtils.rm_f 'temp_one'

    rake "--dry-run"

    refute_match(/No such file/, @out)

    assert_status
  end

  # Test for the trace/dry_run bug found by Brian Chandler
  def test_trace_bug
    rakefile_dryrun

    rake

    FileUtils.rm_f 'temp_one'

    rake "--trace"

    refute_match(/No such file/, @out)
    assert_status
  end

  def test_imports
    rakefile_imports

    rake

    assert File.exist?(File.join(@tempdir, 'dynamic_deps')),
           "'dynamic_deps' file should exist"
    assert_match(/^FIRST$\s+^DYNAMIC$\s+^STATIC$\s+^OTHER$/, @out)
    assert_status
  end

  def test_rules_chaining_to_file_task
    rakefile_chains

    rake

    assert File.exist?(File.join(@tempdir, 'play.app')),
           "'play.app' file should exist"
    assert_status
  end

  def test_file_creation_task
    rakefile_file_creation

    rake "prep"
    rake "run"
    rake "run"

    assert(@err !~ /^cp src/, "Should not recopy data")
  end

  def test_dash_f_with_no_arg_foils_rakefile_lookup
    rakefile_rakelib

    rake "-I rakelib -rtest1 -f"

    assert_match(/^TEST1$/, @out)
  end

  def test_dot_rake_files_can_be_loaded_with_dash_r
    rakefile_rakelib

    rake "-I rakelib -rtest2 -f"

    assert_match(/^TEST2$/, @out)
  end

  def test_can_invoke_task_in_toplevel_namespace
    rakefile_namespace

    rake "copy"

    assert_match(/^COPY$/, @out)
  end

  def test_can_invoke_task_in_nested_namespace
    rakefile_namespace

    rake "nest:copy"

    assert_match(/^NEST COPY$/, @out)
  end

  def test_tasks_can_reference_task_in_same_namespace
    rakefile_namespace

    rake "nest:xx"

    assert_match(/^NEST COPY$/m, @out)
  end

  def test_tasks_can_reference_task_in_other_namespaces
    rakefile_namespace

    rake "b:run"

    assert_match(/^IN A\nIN B$/m, @out)
  end

  def test_anonymous_tasks_can_be_invoked_indirectly
    rakefile_namespace

    rake "anon"

    assert_match(/^ANON COPY$/m, @out)
  end

  def test_rake_namespace_refers_to_toplevel
    rakefile_namespace

    rake "very:nested:run"

    assert_match(/^COPY$/m, @out)
  end

  def test_file_task_are_not_scoped_by_namespaces
    rakefile_namespace

    rake "xyz.rb"

    assert_match(/^XYZ1\nXYZ2$/m, @out)
  end

  def test_file_task_dependencies_scoped_by_namespaces
    rakefile_namespace

    rake "scopedep.rb"

    assert_match(/^PREPARE\nSCOPEDEP$/m, @out)
  end

  def test_rake_returns_status_error_values
    rakefile_statusreturn

    rake "exit5"

    assert_status 5
  end

  def test_rake_returns_no_status_error_on_normal_exit
    rakefile_statusreturn

    rake "normal"

    assert_status 0
  end

  def test_comment_before_task_acts_like_desc
    rakefile_comments

    rake "-T"

    refute_match(/comment for t1/, @out)
  end

  def test_comment_separated_from_task_by_blank_line_is_not_picked_up
    rakefile_comments

    rake "-T"

    refute_match("t2", @out)
  end

  def test_comment_after_desc_is_ignored
    rakefile_comments

    rake "-T"

    assert_match("override comment for t3", @out)
  end

  def test_comment_before_desc_is_ignored
    rakefile_comments

    rake "-T"

    assert_match("override comment for t4", @out)
  end

  def test_correct_number_of_tasks_reported
    rakefile_comments

    rake "-T"

    assert_equal(2, @out.split(/\n/).grep(/t\d/).size)
  end

  def test_file_list_is_requirable_separately
    ruby "-rrake/file_list", "-e 'puts Rake::FileList[\"a\"].size'"
    assert_equal "1\n", @out
    assert_equal 0, @status
  end

  private

  # Run a shell Ruby command with command line options (using the
  # default test options). Output is captured in @out, @err and
  # @status.
  def ruby(*option_list)
    run_ruby(@ruby_options + option_list)
  end

  # Run a command line rake with the give rake options.  Default
  # command line ruby options are included.  Output is captured in
  # @out, @err and @status.
  def rake(*rake_options)
    run_ruby @ruby_options + [@rake_path] + rake_options
  end

  # Low level ruby command runner ...
  def run_ruby(option_list)
    shell = Session::Shell.new
    command = "#{Gem.ruby} #{option_list.join ' '}"
    puts "COMMAND: [#{command}]" if @verbose
    @out, @err = shell.execute command
    @status = shell.exit_status
    puts "STATUS:  [#{@status}]" if @verbose
    puts "OUTPUT:  [#{@out}]" if @verbose
    puts "ERROR:   [#{@err}]" if @verbose
    puts "PWD:     [#{Dir.pwd}]" if @verbose
    shell.close
  end

  def assert_status(expected_status=0)
    assert_equal expected_status, @status
  end
end if defined?(Session)
