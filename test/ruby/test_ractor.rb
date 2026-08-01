# frozen_string_literal: false
require 'test/unit'

class TestRactor < Test::Unit::TestCase
  def test_shareability_of_iseq_proc
    assert_raise Ractor::IsolationError do
      foo = []
      Ractor.shareable_proc{ foo }
    end
  end

  def test_shareability_of_method_proc
    # TODO: fix with Ractor.shareable_proc/lambda
=begin
    str = +""

    x = str.instance_exec { proc { to_s } }
    assert_unshareable(x, /Proc\'s self is not shareable/)

    x = str.instance_exec { method(:to_s) }
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)

    x = str.instance_exec { method(:to_s).to_proc }
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)

    x = str.instance_exec { method(:itself).to_proc }
    assert_unshareable(x, "can not make shareable object for #<Method: String(Kernel)#itself()>", exception: Ractor::Error)

    str.freeze

    x = str.instance_exec { proc { to_s } }
    assert_make_shareable(x)

    x = str.instance_exec { method(:to_s) }
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)

    x = str.instance_exec { method(:to_s).to_proc }
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)

    x = str.instance_exec { method(:itself).to_proc }
    assert_unshareable(x, "can not make shareable object for #<Method: String(Kernel)#itself()>", exception: Ractor::Error)
=end
  end

  def test_shareable_proc_define_method_super_method_missing
    assert_ractor(<<~'RUBY', timeout: 30)
      iterations = 1_000_000

      class SuperFromShareableProcMethodMissingBase
        def method_missing(mid, *) = mid
      end

      class SuperFromShareableProcMethodMissingChild < SuperFromShareableProcMethodMissingBase
        BODY = Ractor.shareable_proc { super() }
        define_method(:foo, &BODY)
        define_method(:bar, &BODY)
      end

      [:foo, :bar].map do |mid|
        Ractor.new(mid, iterations) do |mid, iterations|
          obj = SuperFromShareableProcMethodMissingChild.new
          iterations.times do
            got = obj.__send__(mid)
            raise "#{mid} returned #{got.inspect}" unless got == mid
          end
        end
      end.each(&:value)
    RUBY
  end

  def test_shareable_proc_define_method_super_method_entry
    assert_ractor(<<~'RUBY', timeout: 30)
      iterations = 1_000_000

      class SuperFromShareableProcBase
        def foo = :foo
        def bar = :bar
      end

      class SuperFromShareableProcChild < SuperFromShareableProcBase
        BODY = Ractor.shareable_proc { super() }
        define_method(:foo, &BODY)
        define_method(:bar, &BODY)
      end

      [:foo, :bar].map do |mid|
        Ractor.new(mid, iterations) do |mid, iterations|
          obj = SuperFromShareableProcChild.new
          iterations.times do
            got = obj.__send__(mid)
            raise "#{mid} returned #{got.inspect}" unless got == mid
          end
        end
      end.each(&:value)
    RUBY
  end

  def test_shareability_error_uses_inspect
    x = (+"").instance_exec { method(:to_s) }
    def x.to_s
      raise "this should not be called"
    end
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()> because it refers unshareable objects", exception: Ractor::Error)
  end

  def test_sending_exception_with_backtrace
    assert_ractor(<<~'RUBY')
      def build_error
        raise "Test"
      rescue => error
        error
      end

      error = build_error
      refute_empty error.backtrace
      refute_empty error.backtrace_locations

      backtrace, backtrace_locations = Ractor.new(error) do |error2|
        [error2.backtrace, error2.backtrace_locations]
      end.value

      assert_equal error.backtrace, backtrace
      refute_empty backtrace_locations
    RUBY
  end

  def test_sending_exception_with_array_backtrace
    assert_ractor(<<~'RUBY')
      error = StandardError.new
      error.set_backtrace(["foo", "bar"])
      refute_empty error.backtrace
      assert_nil error.backtrace_locations

      backtrace, backtrace_locations = Ractor.new(error) do |error2|
        [error2.backtrace, error2.backtrace_locations]
      end.value

      assert_equal error.backtrace, backtrace
      assert_nil backtrace_locations
    RUBY
  end

  def test_sending_object_with_broken_clone
    # メッセージの複製はユーザ可視の #clone を呼ばないので、壊れた #clone は送信を
    # 壊せない。代わりに #clone が定義する特異クラスで複製不可になる
    assert_ractor(<<~'RUBY')
      o = Object.new
      def o.clone
        self
      end
      ractor = Ractor.new { Ractor.receive }
      error = assert_raise Ractor::Error do
        ractor.send(o)
      end
      assert_match "can not copy", error.message
    RUBY
  end

  def test_default_thread_group
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      Warning[:experimental] = false

      main_ractor_id = Thread.current.group.object_id
      ractor_id = Ractor.new { Thread.current.group.object_id }.value
      refute_equal main_ractor_id, ractor_id
    end;
  end

  def test_class_instance_variables
    assert_ractor(<<~'RUBY')
      # Once we're in multi-ractor mode, the codepaths
      # for class instance variables are a bit different.
      Ractor.new {}.value

      class TestClass
        @a = 1
        @b = 2
        @c = 3
        @d = 4
      end

      assert_equal 4, TestClass.remove_instance_variable(:@d)
      assert_nil TestClass.instance_variable_get(:@d)
      assert_equal 4, TestClass.instance_variable_set(:@d, 4)
      assert_equal 4, TestClass.instance_variable_get(:@d)
    RUBY
  end


  def test_class_variables
    # [Bug #22072]
    assert_ractor(<<~'RUBY')
      module Foo
        def self.foo = @@foo
      end

      Foo.class_variable_set(:@@foo, 1)

      10.times { |i| Foo.class_variable_set(:"@@bar#{i}", i) }

      assert_equal(Foo.foo, 1)
    RUBY
  end

  def test_struct_instance_variables
    assert_ractor(<<~'RUBY')
      StructIvar = Struct.new(:member) do
        def initialize(*)
          super
          @ivar = "ivar"
        end
        attr_reader :ivar
      end
      obj = StructIvar.new("member")
      obj_copy = Ractor.new { Ractor.receive }.send(obj).value
      assert_equal obj.ivar, obj_copy.ivar
      refute_same obj.ivar, obj_copy.ivar
      assert_equal obj.member, obj_copy.member
      refute_same obj.member, obj_copy.member
    RUBY
  end

  def test_move_nested_hash_during_gc_with_yjit
    assert_ractor(<<~'RUBY', timeout: 20, args: [{ "RUBY_YJIT_ENABLE" => "1" }])
      GC.stress = true
      hash = { foo: { bar: "hello" }, baz: { qux: "there" } }
      result = Ractor.new { Ractor.receive }.send(hash, move: true).value
      assert_equal "hello", result[:foo][:bar]
      assert_equal "there", result[:baz][:qux]
    RUBY
  end

  def test_fork_raise_isolation_error
    assert_ractor(<<~'RUBY')
      ractor = Ractor.new do
        Process.fork
      rescue Ractor::IsolationError => e
        e
      end
      assert_equal Ractor::IsolationError, ractor.value.class
    RUBY
  end if Process.respond_to?(:fork)

  def test_at_exit_raise_isolation_error
    assert_ractor(<<~'RUBY')
      ractor = Ractor.new do
        at_exit { }
      rescue Ractor::IsolationError => e
        e
      end
      assert_equal Ractor::IsolationError, ractor.value.class
    RUBY
  end

  def test_END_raise_isolation_error
    assert_ractor(<<~'RUBY', ignore_stderr: true)
      ractor = Ractor.new do
        END { nil }
      rescue Ractor::IsolationError => e
        e
      end
      assert_equal Ractor::IsolationError, ractor.value.class
    RUBY
  end

  def test_require_raises_and_no_ractor_belonging_issue
    assert_ractor(<<~'RUBY')
      require "tempfile"
      f = Tempfile.new(["file_to_require_from_ractor", ".rb"])
      f.write("raise 'uh oh'")
      f.flush
      err_msg = Ractor.new(f.path) do |path|
        begin
          require path
        rescue RuntimeError => e
          e.message # had confirm belonging issue here
        else
          nil
        end
      end.value
      assert_equal "uh oh", err_msg
    RUBY
  end

  def test_require_non_string
    assert_ractor(<<~'RUBY')
      require "tempfile"
      require "pathname"
      f = Tempfile.new(["file_to_require_from_ractor", ".rb"])
      f.write("")
      f.flush
      result = Ractor.new(f.path) do |path|
        require Pathname.new(path)
        "success"
      end.value
      assert_equal "success", result
    RUBY
  end

  # [Bug #21398]
  def test_port_receive_dnt_with_port_send
    omit 'unstable on windows and macos-14' if RUBY_PLATFORM =~ /mswin|mingw|darwin/
    assert_ractor(<<~'RUBY', timeout: 90)
      THREADS = 10
      JOBS_PER_THREAD = 50
      ARRAY_SIZE = 20_000
      def ractor_job(job_count, array_size)
        port = Ractor::Port.new
        workers = (1..4).map do |i|
          Ractor.new(port) do |job_port|
            while job = Ractor.receive
              result = job.map { |x| x * 2 }.sum
              job_port.send result
            end
          end
        end
        jobs = Array.new(job_count) { Array.new(array_size) { rand(1000) } }
        jobs.each_with_index do |job, i|
          w_idx = i % 4
          workers[w_idx].send(job)
        end
        results = []
        jobs.size.times do
          result = port.receive # dnt receive
          results << result
        end
        results
      end
      threads = []
      # creates 40 ractors (THREADSx4)
      THREADS.times do
        threads << Thread.new do
          ractor_job(JOBS_PER_THREAD, ARRAY_SIZE)
        end
      end
      threads.each(&:join)
    RUBY
  end

  # [Bug #20146]
  def test_max_cpu_1
    assert_ractor(<<~'RUBY', args: [{ "RUBY_MAX_CPU" => "1" }])
      assert_equal :ok, Ractor.new { :ok }.value
    RUBY
  end

  def test_mn_threads
    # Ideally, we would assert that vm->ractor.sched.max_cpu equals sysconf(_SC_NPROCESSORS_ONLN)
    # when RUBY_MAX_CPU is not set.
    assert_ractor(<<~'RUBY', args: [{ "RUBY_MN_THREADS" => "1" }])
      require "etc"
      n = Etc.respond_to?(:nprocessors) ? Etc.nprocessors : 8
      rs = n.times.map { Ractor.new { :ok } }
      assert_equal [:ok] * n, rs.map(&:value)
    RUBY
  end

  def test_symbol_proc_is_shareable
    pr = :symbol.to_proc
    assert_make_shareable(pr)
  end

  # [Bug #21775]
  def test_ifunc_proc_not_shareable
    h = Hash.new { self }
    pr = h.to_proc
    assert_unshareable(pr, /not supported yet/, exception: RuntimeError)
  end

  def test_copy_unshareable_object_error_message
    assert_ractor(<<~'RUBY')
      pr = proc {}
      err = assert_raise(Ractor::Error) do
        Ractor.new(pr) {}.join
      end
      assert_match(/can not copy Proc object/, err.message)
    RUBY
  end

  def test_ractor_new_raises_isolation_error_if_outer_variables_are_accessed
    assert_raise(Ractor::IsolationError) do
      channel = Ractor::Port.new
      Ractor.new(channel) do
        inbound_work = Ractor::Port.new
        channel << inbound_work
      end
    end
  end

  def test_ractor_new_raises_isolation_error_if_proc_uses_yield
    assert_raise(Ractor::IsolationError) do
      Ractor.new do
        yield
      end
    end
  end

  def test_ractor_does_not_inherit_fiber_storage
    assert_ractor(<<~'RUBY')
      Fiber[:key] = "creator"
      assert_nil Ractor.new { Fiber[:key] }.value
    RUBY
  end

  def test_detailed_message_in_ractor
    # The error decoration gems (error_highlight, did_you_mean, and
    # syntax_suggest) are loaded lazily on the first error display. In a
    # non-main Ractor the require is delegated to the main Ractor, so the
    # decorations must appear there too. [Feature #21951]
    assert_ractor(<<~'RUBY', args: ["--enable=gems"], ignore_stderr: true)
      message = Ractor.new do
        begin
          1.timess
        rescue NoMethodError => e
          e.detailed_message(highlight: false)
        end
      end.value
      assert_include(message, "timess")
      assert_include(message, "Did you mean?")
    RUBY
  end

  # per-Ractor GC では finalizer の登録・テーブル・実行はすべてオブジェクトの
  # Ractor に属する。他 Ractor のオブジェクト（shareable も含む）への定義は拒否する
  def test_define_finalizer_on_foreign_object
    omit 'per-Ractor objspace semantics of the default GC' unless GC.config[:implementation] == 'default'
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      Warning[:experimental] = false
      r = Ractor.new do
        results = []
        own = Object.new
        ObjectSpace.define_finalizer(own, proc {})
        results << :own_ok
        begin
          ObjectSpace.define_finalizer(String, proc {})  # main's class
          results << :define_did_not_raise
        rescue Ractor::IsolationError
          results << :define_raised
        end
        begin
          ObjectSpace.undefine_finalizer(String)
          results << :undefine_did_not_raise
        rescue Ractor::IsolationError
          results << :undefine_raised
        end
        results
      end
      assert_equal [:own_ok, :define_raised, :undefine_raised], r.value
      GC.verify_internal_consistency
    RUBY
  end

  # ObjectSpace.each_object は呼び出し元 Ractor 自身の objspace の全オブジェクトと、
  # 他の生存 Ractor が持つ shareable を列挙する（他 Ractor の unshareable は列挙しない）
  def test_each_object_own_all_and_foreign_shareables
    omit 'per-Ractor objspace semantics of the default GC' unless GC.config[:implementation] == 'default'
    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      Warning[:experimental] = false
      class Marker; end
      main_un = 5.times.map { Marker.new }
      main_sh = 3.times.map { Ractor.make_shareable(Marker.new) }
      ready = Ractor::Port.new
      ch = Ractor.new(ready) do |ready_port|
        un = 7.times.map { Marker.new }               # unshareable なので見えてはならない
        sh = 4.times.map { Ractor.make_shareable(Marker.new) }
        ready_port << :built
        Ractor.receive                                # この objspace を生かし続ける
        [un.size, sh.size]
      end
      ready.receive                                   # 子がマーカーを作り終えた

      seen = 0
      ObjectSpace.each_object(Marker) { seen += 1 }
      # 自分の 8（unshareable 5 + shareable 3）＋子の shareable 4
      assert_equal 12, seen

      ch.send(:go)
      ch.value
      # 走査中もルートを生かしておく
      assert_equal 5, main_un.size
      assert_equal 3, main_sh.size
    RUBY
  end

  # Ractor.new が IsolationError で失敗（stillborn）しても、作成途中の
  # objspace の後始末が漏れないこと（二重列挙/解放後読みの regression guard）
  def test_stillborn_ractor_gc
    assert_ractor(<<~'RUBY', timeout: 60)
      x = 42 # 外側ローカルの捕捉 => Ractor.new で IsolationError
      worker = Ractor.new { loop { break if Ractor.receive == :quit } }
      assert_raise(Ractor::IsolationError) { Ractor.new { x } }
      10.times { GC.start; 500.times { Object.new } }
      GC.verify_internal_consistency
      worker.send(:quit)
      worker.value
      100.times do |i|
        assert_raise(Ractor::IsolationError) { Ractor.new { x } }
        if (i % 20).zero?
          Ractor.new { :ok }.value
          GC.start
        end
      end
      GC.start
      GC.verify_internal_consistency
    RUBY
  end

  # CoW 共有 ROOT な String の move は buffer を奪ってはならない
  # （残った共有者が解放済み buffer を読む regression guard）
  def test_move_shared_root_string_keeps_buffer
    assert_ractor(<<~'RUBY', timeout: 60)
      10.times do
        r = Ractor.new { Ractor.receive.bytesize; :done }
        f = "x" * 4096
        f.instance_variable_set(:@x, []) # unshareable ivar => 参照渡しでなく move
        f.freeze
        g = f.dup                # f の buffer を共有 -> f は shared root
        h = f[10, 3000]          # 長い substring も buffer を共有
        r.send(f, move: true)
        r.value
        GC.start
        10.times { "z" * 4096 }
        assert_equal "x" * 4096, g
        assert_equal "x" * 3000, h
      end
    RUBY
  end

  # GC.stress 下の Ractor::Port.new が deadlock しないこと
  # （ractor lock 保持中の malloc からの stress GC の regression guard）
  def test_port_new_under_gc_stress
    assert_ractor(<<~'RUBY', timeout: 90)
      GC.stress = true
      ports = 4.times.map { Ractor::Port.new }
      GC.stress = false
      assert_equal 4, ports.size
    RUBY
  end

  # Hash を key に持つ Hash の move で entry が失われないこと
  # （key の中身が埋まる前に挿入すると hash 値が壊れる regression guard）
  def test_move_hash_with_hash_keys
    assert_ractor(<<~'RUBY', timeout: 60)
      k1 = { a: 1 }; k2 = { b: 2 }
      h = { k1 => :v1, k2 => :v2, { c: { d: 3 } } => :v3 }
      r = Ractor.new { Ractor.receive }
      r.send(h, move: true)
      m = r.value
      assert_equal 3, m.size
      assert_equal :v1, m[{ a: 1 }]
      assert_equal :v2, m[{ b: 2 }]
      assert_equal :v3, m[{ c: { d: 3 } }]
    RUBY
  end

  # copy send の in-flight snapshot は GC.compact で動いてはならない
  # （generic-ivar 同梱表と dedup 表はアドレスキーのため。YJIT で決定論再現した形）
  def test_copy_genivar_snapshot_survives_compact
    omit 'GC.compact is unimplemented' unless GC.config[:implementation] == 'default'
    assert_ractor(<<~'RUBY', timeout: 60, args: [{ "RUBY_YJIT_ENABLE" => "1" }])
      port = Ractor::Port.new
      w = Ractor.new(port) do |po|
        mm = Ractor.receive
        res = mm.map { |ss| [ss, ss.frozen?, ss.instance_variable_get(:@sku)] }
        po.send(res)
      end
      items = 4.times.map do |i|
        s = +"item-#{i}"
        s.instance_variable_set(:@sku, "SKU#{1000 + i}")
        s.freeze
      end
      w.send(items)
      GC.compact
      res = port.receive
      res.each_with_index do |(txt, fz, sku), i|
        assert_equal "item-#{i}", txt
        assert fz
        assert_equal "SKU#{1000 + i}", sku
      end
    RUBY
  end

  # move が String/Array/Hash のサブクラスの class を保持すること
  def test_move_preserves_subclass
    assert_ractor(<<~'RUBY', timeout: 60)
      class MyStr < String; end
      class MyArr < Array; end
      class MyHash < Hash; end
      s = MyStr.new("hello"); a = MyArr.new([1, 2]); h = MyHash.new; h[:k] = 1
      r = Ractor.new { 3.times.map { Ractor.receive } }
      r.send(s, move: true); r.send(a, move: true); r.send(h, move: true)
      rs, ra, rh = r.value
      assert_equal [MyStr, MyArr, MyHash], [rs.class, ra.class, rh.class]
      assert_equal "hello", rs
      assert_equal [1, 2], ra
      assert_equal 1, rh[:k]
    RUBY
  end

  def test_bignum_to_s
    assert_ractor(<<~'RUBY')
      8.times.map do
        Ractor.new do
          1_000.times do |i|
            v = (2**96 - 1) + i
            s = v.to_s
            # round-trip through str2big (uses the same cache)
            raise "bad to_s: #{s.inspect}" unless Integer(s) == v
          end
        end
      end.each(&:join)
    RUBY
  end

  def assert_make_shareable(obj)
    refute Ractor.shareable?(obj), "object was already shareable"
    Ractor.make_shareable(obj)
    assert Ractor.shareable?(obj), "object didn't become shareable"
  end

  def assert_unshareable(obj, msg=nil, exception: Ractor::IsolationError)
    refute Ractor.shareable?(obj), "object is already shareable"
    assert_raise_with_message(exception, msg) do
      Ractor.make_shareable(obj)
    end
    refute Ractor.shareable?(obj), "despite raising, object became shareable"
  end
end
