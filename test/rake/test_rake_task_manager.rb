require File.expand_path('../helper', __FILE__)

class TestRakeTaskManager < Rake::TestCase

  def setup
    super

    @tm = Rake::TestCase::TaskManager.new
  end

  def test_create_task_manager
    refute_nil @tm
    assert_equal [], @tm.tasks
  end

  def test_define_task
    t = @tm.define_task(Rake::Task, :t)
    assert_equal "t", t.name
    assert_equal @tm, t.application
  end

  def test_index
    e = assert_raises RuntimeError do
      @tm['bad']
    end

    assert_equal "Don't know how to build task 'bad'", e.message
  end

  def test_name_lookup
    t = @tm.define_task(Rake::Task, :t)
    assert_equal t, @tm[:t]
  end

  def test_namespace_task_create
    @tm.in_namespace("x") do
      t = @tm.define_task(Rake::Task, :t)
      assert_equal "x:t", t.name
    end
    assert_equal ["x:t"], @tm.tasks.map { |t| t.name }
  end

  def test_define_namespaced_task
    t = @tm.define_task(Rake::Task, 'n:a:m:e:t')
    assert_equal Rake::Scope.make("e", "m", "a", "n"), t.scope
    assert_equal "n:a:m:e:t", t.name
    assert_equal @tm, t.application
  end

  def test_define_namespace_in_namespace
    t = nil
    @tm.in_namespace("n") do
      t = @tm.define_task(Rake::Task, 'a:m:e:t')
    end
    assert_equal Rake::Scope.make("e", "m", "a", "n"), t.scope
    assert_equal "n:a:m:e:t", t.name
    assert_equal @tm, t.application
  end

  def test_anonymous_namespace
    anon_ns = @tm.in_namespace(nil) do
      t = @tm.define_task(Rake::Task, :t)
      assert_equal "_anon_1:t", t.name
    end
    task = anon_ns[:t]
    assert_equal "_anon_1:t", task.name
  end

  def test_create_filetask_in_namespace
    @tm.in_namespace("x") do
      t = @tm.define_task(Rake::FileTask, "fn")
      assert_equal "fn", t.name
    end

    assert_equal ["fn"], @tm.tasks.map { |t| t.name }
  end

  def test_namespace_yields_same_namespace_as_returned
    yielded_namespace = nil
    returned_namespace = @tm.in_namespace("x") do |ns|
      yielded_namespace = ns
    end
    assert_equal returned_namespace, yielded_namespace
  end

  def test_name_lookup_with_implicit_file_tasks
    FileUtils.touch 'README.rdoc'

    t = @tm["README.rdoc"]

    assert_equal "README.rdoc", t.name
    assert Rake::FileTask === t
  end

  def test_name_lookup_with_nonexistent_task
    assert_raises(RuntimeError) {
      @tm["DOES NOT EXIST"]
    }
  end

  def test_name_lookup_in_multiple_scopes
    aa = nil
    bb = nil
    xx = @tm.define_task(Rake::Task, :xx)
    top_z = @tm.define_task(Rake::Task, :z)
    @tm.in_namespace("a") do
      aa = @tm.define_task(Rake::Task, :aa)
      mid_z = @tm.define_task(Rake::Task, :z)
      ns_d = @tm.define_task(Rake::Task, "n:t")
      @tm.in_namespace("b") do
        bb = @tm.define_task(Rake::Task, :bb)
        bot_z = @tm.define_task(Rake::Task, :z)

        assert_equal Rake::Scope.make("b", "a"), @tm.current_scope

        assert_equal bb, @tm["a:b:bb"]
        assert_equal aa, @tm["a:aa"]
        assert_equal xx, @tm["xx"]
        assert_equal bot_z, @tm["z"]
        assert_equal mid_z, @tm["^z"]
        assert_equal top_z, @tm["^^z"]
        assert_equal top_z, @tm["^^^z"] # Over the top
        assert_equal top_z, @tm["rake:z"]
      end

      assert_equal Rake::Scope.make("a"), @tm.current_scope

      assert_equal bb, @tm["a:b:bb"]
      assert_equal aa, @tm["a:aa"]
      assert_equal xx, @tm["xx"]
      assert_equal bb, @tm["b:bb"]
      assert_equal aa, @tm["aa"]
      assert_equal mid_z, @tm["z"]
      assert_equal top_z, @tm["^z"]
      assert_equal top_z, @tm["^^z"] # Over the top
      assert_equal top_z, @tm["rake:z"]
      assert_equal ns_d, @tm["n:t"]
      assert_equal ns_d, @tm["a:n:t"]
    end

    assert_equal Rake::Scope.make, @tm.current_scope

    assert_equal Rake::Scope.make, xx.scope
    assert_equal Rake::Scope.make('a'), aa.scope
    assert_equal Rake::Scope.make('b', 'a'), bb.scope
  end

  def test_lookup_with_explicit_scopes
    t1, t2, t3, s = (0...4).map { nil }
    t1 = @tm.define_task(Rake::Task, :t)
    @tm.in_namespace("a") do
      t2 = @tm.define_task(Rake::Task, :t)
      s =  @tm.define_task(Rake::Task, :s)
      @tm.in_namespace("b") do
        t3 = @tm.define_task(Rake::Task, :t)
      end
    end
    assert_equal t1, @tm[:t, Rake::Scope.make]
    assert_equal t2, @tm[:t, Rake::Scope.make("a")]
    assert_equal t3, @tm[:t, Rake::Scope.make("b", "a")]
    assert_equal s,  @tm[:s, Rake::Scope.make("b", "a")]
    assert_equal s,  @tm[:s, Rake::Scope.make("a")]
  end

  def test_correctly_scoped_prerequisites_are_invoked
    values = []
    @tm = Rake::Application.new
    @tm.define_task(Rake::Task, :z) do values << "top z" end
    @tm.in_namespace("a") do
      @tm.define_task(Rake::Task, :z) do values << "next z" end
      @tm.define_task(Rake::Task, :x => :z)
    end

    @tm["a:x"].invoke
    assert_equal ["next z"], values
  end

end
