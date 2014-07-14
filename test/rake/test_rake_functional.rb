require File.expand_path('../helper', __FILE__)
require 'fileutils'
require 'open3'

class TestRakeFunctional < Rake::TestCase
  include RubyRunner

  def setup
    super

    if @verbose
      puts
      puts
      puts '-' * 80
      puts @__name__
      puts '-' * 80
    end
  end

  def test_rake_default
    rakefile_default

    rake

    assert_match(/^DEFAULT$/, @out)
  end

  def test_rake_error_on_bad_task
    rakefile_default

    rake '-t', 'xyz'

    assert_match(/rake aborted/, @err)
  end

  def test_env_available_at_top_scope
    rakefile_default

    rake "TESTTOPSCOPE=1"

    assert_match(/^TOPSCOPE$/, @out)
  end

  def test_env_available_at_task_scope
    rakefile_default

    rake 'TESTTASKSCOPE=1', 'task_scope'

    assert_match(/^TASKSCOPE$/, @out)
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

    assert_match %r{^rake a\n *A\n *A2 *$}m, @out
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

    assert_match(/#{Regexp.quote(RUBY)} -e/, @err)
  end

  def test_inline_verbose_true_should_show_command
    rakefile_verbose

    rake "inline_verbose_true"

    assert_match(/#{Regexp.quote(RUBY)} -e/, @err)
  end

  def test_inline_verbose_false_should_not_show_command
    rakefile_verbose

    rake "inline_verbose_false"

    refute_match(/#{Regexp.quote(RUBY)} -e/, @err)
  end

  def test_block_verbose_false_should_not_show_command
    rakefile_verbose

    rake "block_verbose_false"

    refute_match(/#{Regexp.quote(RUBY)} -e/, @err)
  end

  def test_block_verbose_true_should_show_command
    rakefile_verbose

    rake "block_verbose_true"

    assert_match(/#{Regexp.quote(RUBY)} -e/, @err)
  end

  def test_standalone_verbose_true_should_show_command
    rakefile_verbose

    rake "standalone_verbose_true"

    assert_match(/#{Regexp.quote(RUBY)} -e/, @err)
  end

  def test_standalone_verbose_false_should_not_show_command
    rakefile_verbose

    rake "standalone_verbose_false"

    refute_match(/#{Regexp.quote(RUBY)} -e/, @err)
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
  end

  # Test for the trace/dry_run bug found by Brian Chandler
  def test_trace_bug
    rakefile_dryrun

    rake

    FileUtils.rm_f 'temp_one'

    rake "--trace"

    refute_match(/No such file/, @out)
  end

  def test_imports
    rakefile_imports

    rake

    assert File.exist?(File.join(@tempdir, 'dynamic_deps')),
           "'dynamic_deps' file should exist"
    assert_match(/^FIRST$\s+^DYNAMIC$\s+^STATIC$\s+^OTHER$/, @out)
  end

  def test_regenerate_imports
    rakefile_regenerate_imports

    rake

    assert_match(/^INITIAL\s+^REGENERATED$/, @out)
  end

  def test_rules_chaining_to_file_task
    rakefile_chains

    rake

    assert File.exist?(File.join(@tempdir, 'play.app')),
           "'play.app' file should exist"
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

    rake '-I', 'rakelib', '-rtest1', '-f'

    assert_match(/^TEST1$/, @out)
  end

  def test_dot_rake_files_can_be_loaded_with_dash_r
    rakefile_rakelib

    rake '-I', 'rakelib', '-rtest2', '-f'

    assert_empty @err
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

  def test_test_task_descriptions
    rakefile_test_task

    rake "-T"

    assert_match(/custom test task description/, @out)
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
    ruby '-rrake/file_list', '-e', 'puts Rake::FileList["a"].size'
    assert_equal "1\n", @out
  end

  def can_detect_signals?
    system RUBY, '-e', 'Process.kill "TERM", $$'
    status = $?
    if @verbose
      puts "    SIG status = #{$?.inspect}"
      puts "    SIG status.respond_to?(:signaled?) = " +
        "#{$?.respond_to?(:signaled?).inspect}"
      puts "    SIG status.signaled? = #{status.signaled?}" if
        status.respond_to?(:signaled?)
    end
    status.respond_to?(:signaled?) && status.signaled?
  end

  def test_signal_propagation_in_tests
    if can_detect_signals?
      rakefile_test_signal
      rake
      assert_match(/ATEST/, @out)
      refute_match(/BTEST/, @out)
    else
      skip "Signal detect seems broken on this system"
    end
  end

  def test_failing_test_sets_exit_status
    skip if uncertain_exit_status?
    rakefile_failing_test_task
    rake
    assert @exit.exitstatus > 0, "should be non-zero"
  end

  def test_stand_alone_filelist
    rakefile_stand_alone_filelist

    run_ruby @ruby_options + ["stand_alone_filelist.rb"]

    assert_match(/^stand_alone_filelist\.rb$/, @out)
    assert_equal 0, @exit.exitstatus unless uncertain_exit_status?
  end

  private

  # We are unable to accurately verify that Rake returns a proper
  # error exit status using popen3 in Ruby 1.8.7 and JRuby. This
  # predicate function can be used to skip tests or assertions as
  # needed.
  def uncertain_exit_status?
    RUBY_VERSION < "1.9" || defined?(JRUBY_VERSION)
  end

end
