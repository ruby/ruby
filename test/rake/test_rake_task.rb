require File.expand_path('../helper', __FILE__)
require 'fileutils'

class TestRakeTask < Rake::TestCase
  include Rake

  def setup
    super

    Task.clear
    Rake::TaskManager.record_task_metadata = true
  end

  def teardown
    Rake::TaskManager.record_task_metadata = false
    Rake.application.thread_pool.join

    super
  end

  def test_create
    arg = nil
    t = task(:name) { |task| arg = task; 1234 }
    assert_equal "name", t.name
    assert_equal [], t.prerequisites
    assert t.needed?
    t.execute(0)
    assert_equal t, arg
    assert_nil t.source
    assert_equal [], t.sources
    assert_equal 1, t.locations.size
    assert_match(/#{Regexp.quote(__FILE__)}/, t.locations.first)
  end

  def test_inspect
    t = task(:foo => [:bar, :baz])
    assert_equal "<Rake::Task foo => [bar, baz]>", t.inspect
  end

  def test_invoke
    runlist = []
    t1 = task(:t1 => [:t2, :t3]) { |t| runlist << t.name; 3321 }
    task(:t2) { |t| runlist << t.name }
    task(:t3) { |t| runlist << t.name }
    assert_equal ["t2", "t3"], t1.prerequisites
    t1.invoke
    assert_equal ["t2", "t3", "t1"], runlist
  end

  def test_invoke_with_circular_dependencies
    runlist = []
    t1 = task(:t1 => [:t2]) { |t| runlist << t.name; 3321 }
    t2 = task(:t2 => [:t1]) { |t| runlist << t.name }
    assert_equal ["t2"], t1.prerequisites
    assert_equal ["t1"], t2.prerequisites
    ex = assert_raises RuntimeError do
      t1.invoke
    end
    assert_match(/circular dependency/i, ex.message)
    assert_match(/t1 => t2 => t1/, ex.message)
  end

  def test_dry_run_prevents_actions
    Rake.application.options.dryrun = true
    runlist = []
    t1 = task(:t1) { |t| runlist << t.name; 3321 }
    _, err = capture_io { t1.invoke }
    assert_match(/execute .*t1/i, err)
    assert_match(/dry run/i, err)
    refute_match(/invoke/i, err)
    assert_equal [], runlist
  ensure
    Rake.application.options.dryrun = false
  end

  def test_tasks_can_be_traced
    Rake.application.options.trace = true
    t1 = task(:t1)
    _, err = capture_io {
      t1.invoke
    }
    assert_match(/invoke t1/i, err)
    assert_match(/execute t1/i, err)
  ensure
    Rake.application.options.trace = false
  end

  def test_no_double_invoke
    runlist = []
    t1 = task(:t1 => [:t2, :t3]) { |t| runlist << t.name; 3321 }
    task(:t2 => [:t3]) { |t| runlist << t.name }
    task(:t3) { |t| runlist << t.name }
    t1.invoke
    assert_equal ["t3", "t2", "t1"], runlist
  end

  def test_can_double_invoke_with_reenable
    runlist = []
    t1 = task(:t1) { |t| runlist << t.name }
    t1.invoke
    t1.reenable
    t1.invoke
    assert_equal ["t1", "t1"], runlist
  end

  def test_clear
    desc "a task"
    t = task("t" => "a") { }
    t.clear
    assert t.prerequisites.empty?, "prerequisites should be empty"
    assert t.actions.empty?, "actions should be empty"
    assert_nil t.comment, "comments should be empty"
  end

  def test_clear_prerequisites
    t = task("t" => ["a", "b"])
    assert_equal ['a', 'b'], t.prerequisites
    t.clear_prerequisites
    assert_equal [], t.prerequisites
  end

  def test_clear_actions
    t = task("t") { }
    t.clear_actions
    assert t.actions.empty?, "actions should be empty"
  end

  def test_clear_comments
    desc "the original foo"
    task :foo => [:x] do
      # Dummy action
    end

    task(:foo).clear_comments

    desc "a slightly different foo"
    task :foo

    assert_equal "a slightly different foo", task(:foo).comment
    assert_equal ["x"], task(:foo).prerequisites
    assert_equal 1, task(:foo).actions.size
  end

  def test_find
    task :tfind
    assert_equal "tfind", Task[:tfind].name
    ex = assert_raises(RuntimeError) { Task[:leaves] }
    assert_equal "Don't know how to build task 'leaves'", ex.message
  end

  def test_defined
    assert ! Task.task_defined?(:a)
    task :a
    assert Task.task_defined?(:a)
  end

  def test_multi_invocations
    runs = []
    p = proc do |t| runs << t.name end
    task({ :t1 => [:t2, :t3] }, &p)
    task({ :t2 => [:t3] }, &p)
    task(:t3, &p)
    Task[:t1].invoke
    assert_equal ["t1", "t2", "t3"], runs.sort
  end

  def test_task_list
    task :t2
    task :t1 => [:t2]
    assert_equal ["t1", "t2"], Task.tasks.map { |t| t.name }
  end

  def test_task_gives_name_on_to_s
    task :abc
    assert_equal "abc", Task[:abc].to_s
  end

  def test_symbols_can_be_prerequisites
    task :a => :b
    assert_equal ["b"], Task[:a].prerequisites
  end

  def test_strings_can_be_prerequisites
    task :a => "b"
    assert_equal ["b"], Task[:a].prerequisites
  end

  def test_arrays_can_be_prerequisites
    task :a => ["b", "c"]
    assert_equal ["b", "c"], Task[:a].prerequisites
  end

  def test_filelists_can_be_prerequisites
    task :a => FileList.new.include("b", "c")
    assert_equal ["b", "c"], Task[:a].prerequisites
  end

  def test_prerequiste_tasks_returns_tasks_not_strings
    a = task :a => ["b", "c"]
    b = task :b
    c = task :c
    assert_equal [b, c], a.prerequisite_tasks
  end

  def test_prerequiste_tasks_fails_if_prerequisites_are_undefined
    a = task :a => ["b", "c"]
    task :b
    assert_raises(RuntimeError) do
      a.prerequisite_tasks
    end
  end

  def test_prerequiste_tasks_honors_namespaces
    a = b = nil
    namespace "X" do
      a = task :a => ["b", "c"]
      b = task :b
    end
    c = task :c

    assert_equal [b, c], a.prerequisite_tasks
  end

  def test_all_prerequisite_tasks_includes_all_prerequisites
    a = task :a => "b"
    b = task :b => ["c", "d"]
    c = task :c => "e"
    d = task :d
    e = task :e

    assert_equal [b, c, d, e], a.all_prerequisite_tasks.sort_by { |t| t.name }
  end

  def test_all_prerequisite_tasks_does_not_include_duplicates
    a = task :a => ["b", "c"]
    b = task :b => "c"
    c = task :c

    assert_equal [b, c], a.all_prerequisite_tasks.sort_by { |t| t.name }
  end

  def test_all_prerequisite_tasks_includes_self_on_cyclic_dependencies
    a = task :a => "b"
    b = task :b => "a"

    assert_equal [a, b], a.all_prerequisite_tasks.sort_by { |t| t.name }
  end

  def test_timestamp_returns_now_if_all_prereqs_have_no_times
    a = task :a => ["b", "c"]
    task :b
    task :c

    assert_in_delta Time.now, a.timestamp, 0.1, 'computer too slow?'
  end

  def test_timestamp_returns_latest_prereq_timestamp
    a = task :a => ["b", "c"]
    b = task :b
    c = task :c

    now = Time.now
    def b.timestamp() Time.now + 10 end
    def c.timestamp() Time.now + 5 end

    assert_in_delta now, a.timestamp, 0.1, 'computer too slow?'
  end

  def test_always_multitask
    mx = Mutex.new
    result = []

    t_a = task(:a) do |t|
      sleep 0.2
      mx.synchronize { result << t.name }
    end

    t_b = task(:b) do |t|
      mx.synchronize { result << t.name }
    end

    t_c = task(:c => [:a, :b]) do |t|
      mx.synchronize { result << t.name }
    end

    t_c.invoke

    # task should always run in order
    assert_equal ['a', 'b', 'c'], result

    [t_a, t_b, t_c].each { |t| t.reenable }
    result.clear

    Rake.application.options.always_multitask = true
    t_c.invoke

    # with multitask, task 'b' should grab the mutex first
    assert_equal ['b', 'a', 'c'], result
  end

  def test_investigation_output
    t1 = task(:t1 => [:t2, :t3]) { |t| runlist << t.name; 3321 }
    task(:t2)
    task(:t3)
    out = t1.investigation
    assert_match(/class:\s*Rake::Task/, out)
    assert_match(/needed:\s*true/, out)
    assert_match(/pre-requisites:\s*--t[23]/, out)
  end

  # NOTE: Rail-ties uses comment=.
  def test_comment_setting
    t = task(:t, :name, :rev)
    t.comment = "A Comment"
    assert_equal "A Comment", t.comment
  end

  def test_comments_with_sentences
    desc "Comment 1. Comment 2."
    t = task(:t, :name, :rev)
    assert_equal "Comment 1", t.comment
  end

  def test_comments_with_tabbed_sentences
    desc "Comment 1.\tComment 2."
    t = task(:t, :name, :rev)
    assert_equal "Comment 1", t.comment
  end

  def test_comments_with_decimal_points
    desc "Revision 1.2.3."
    t = task(:t, :name, :rev)
    assert_equal "Revision 1.2.3", t.comment
  end

  def test_comments_do_not_set
    t = task(:t, :name, :rev)
    assert_equal nil, t.comment
  end

  def test_comments_is_nil
    t = task(:t, :name, :rev)
    t.comment = nil
    assert_equal nil, t.comment
  end

  def test_extended_comments
    desc %{
      This is a comment.

      And this is the extended comment.
      name -- Name of task to execute.
      rev  -- Software revision to use.
    }
    t = task(:t, :name, :rev)
    assert_equal "[name,rev]", t.arg_description
    assert_equal "This is a comment", t.comment
    assert_match(/^\s*name -- Name/, t.full_comment)
    assert_match(/^\s*rev  -- Software/, t.full_comment)
    assert_match(/\A\s*This is a comment\.$/, t.full_comment)
  end

  def test_multiple_comments
    desc "line one"
    t = task(:t)
    desc "line two"
    task(:t)
    assert_equal "line one / line two", t.comment
  end

  def test_duplicate_comments
    desc "line one"
    t = task(:t)
    desc "line one"
    task(:t)
    assert_equal "line one", t.comment
  end

  def test_interspersed_duplicate_comments
    desc "line one"
    t = task(:t)
    desc "line two"
    task(:t)
    desc "line one"
    task(:t)
    assert_equal "line one / line two", t.comment
  end

  def test_source_is_first_prerequisite
    t = task :t => ["preqA", "preqB"]
    assert_equal "preqA", t.source
  end
end
