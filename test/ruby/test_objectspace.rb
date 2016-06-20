# frozen_string_literal: false
require 'test/unit'

class TestObjectSpace < Test::Unit::TestCase
  def self.deftest_id2ref(obj)
    /:(\d+)/ =~ caller[0]
    file = $`
    line = $1.to_i
    code = <<"End"
    define_method("test_id2ref_#{line}") {\
      o = ObjectSpace._id2ref(obj.object_id);\
      assert_same(obj, o, "didn't round trip: \#{obj.inspect}");\
    }
End
    eval code, binding, file, line
  end

  deftest_id2ref(-0x4000000000000001)
  deftest_id2ref(-0x4000000000000000)
  deftest_id2ref(-0x40000001)
  deftest_id2ref(-0x40000000)
  deftest_id2ref(-1)
  deftest_id2ref(0)
  deftest_id2ref(1)
  deftest_id2ref(0x3fffffff)
  deftest_id2ref(0x40000000)
  deftest_id2ref(0x3fffffffffffffff)
  deftest_id2ref(0x4000000000000000)
  deftest_id2ref(:a)
  deftest_id2ref(:abcdefghijilkjl)
  deftest_id2ref(:==)
  deftest_id2ref(Object.new)
  deftest_id2ref(self)
  deftest_id2ref(true)
  deftest_id2ref(false)
  deftest_id2ref(nil)

  def test_count_objects
    h = {}
    ObjectSpace.count_objects(h)
    assert_kind_of(Hash, h)
    assert_empty(h.keys.delete_if {|x| x.is_a?(Symbol) || x.is_a?(Integer) })
    assert_empty(h.values.delete_if {|x| x.is_a?(Integer) })

    h = ObjectSpace.count_objects
    assert_kind_of(Hash, h)
    assert_empty(h.keys.delete_if {|x| x.is_a?(Symbol) || x.is_a?(Integer) })
    assert_empty(h.values.delete_if {|x| x.is_a?(Integer) })

    assert_raise(TypeError) { ObjectSpace.count_objects(1) }

    h0 = {:T_FOO=>1000}
    h = ObjectSpace.count_objects(h0)
    assert_same(h0, h)
    assert_equal(0, h0[:T_FOO])
  end

  def test_finalizer
    assert_in_out_err(["-e", <<-END], "", %w(:ok :ok :ok :ok), [])
      a = []
      ObjectSpace.define_finalizer(a) { p :ok }
      b = a.dup
      ObjectSpace.define_finalizer(a) { p :ok }
      !b
    END
    assert_raise(ArgumentError) { ObjectSpace.define_finalizer([], Object.new) }

    code = proc do |priv|
      <<-"CODE"
      fin = Object.new
      class << fin
        #{priv}def call(id)
          puts "finalized"
        end
      end
      ObjectSpace.define_finalizer([], fin)
      CODE
    end
    assert_in_out_err([], code[""], ["finalized"])
    assert_in_out_err([], code["private "], ["finalized"])
    c = EnvUtil.labeled_class("C\u{3042}").new
    o = Object.new
    assert_raise_with_message(ArgumentError, /C\u{3042}/) {
      ObjectSpace.define_finalizer(o, c)
    }
  end

  def test_finalizer_with_super
    assert_in_out_err(["-e", <<-END], "", %w(:ok), [])
      class A
        def foo
        end
      end

      class B < A
        def foo
          1.times { super }
        end
      end

      class C
        module M
        end

        FINALIZER = proc do
          M.module_eval do
          end
        end

        def define_finalizer
          ObjectSpace.define_finalizer(self, FINALIZER)
        end
      end

      class D
        def foo
          B.new.foo
        end
      end

      C::M.singleton_class.send :define_method, :module_eval do |src, id, line|
      end

      GC.stress = true
      10.times do
        C.new.define_finalizer
        D.new.foo
      end

      p :ok
    END
  end

  def test_each_object
    klass = Class.new
    new_obj = klass.new

    found = []
    count = ObjectSpace.each_object(klass) do |obj|
      found << obj
    end
    assert_equal(1, count)
    assert_equal(1, found.size)
    assert_same(new_obj, found[0])
  end

  def test_each_object_enumerator
    klass = Class.new
    new_obj = klass.new

    found = []
    counter = ObjectSpace.each_object(klass)
    assert_equal(1, counter.each {|obj| found << obj})
    assert_equal(1, found.size)
    assert_same(new_obj, found[0])
  end

  def test_each_object_no_gabage
    assert_separately([], <<-End)
    GC.disable
    eval('begin; 1.times{}; rescue; ensure; end')
    arys = []
    ObjectSpace.each_object(Array){|ary|
      arys << ary
    }
    GC.enable
    arys.each{|ary|
      begin
        assert_equal(String, ary.inspect.class) # should not cause SEGV
      rescue RuntimeError
        # rescue "can't modify frozen File" error.
      end
    }
    End
  end

  def test_each_object_recursive_key
    assert_normal_exit(<<-'end;', '[ruby-core:66742] [Bug #10579]')
      h = {["foo"]=>nil}
      p Thread.current[:__recursive_key__]
    end;
  end

  def test_each_object_singleton_class
    assert_separately([], <<-End)
      class C
        class << self
          $c = self
        end
      end

      exist = false
      ObjectSpace.each_object(Class){|o|
        exist = true if $c == o
      }
      assert(exist, 'Bug #11360')
    End

    klass = Class.new
    instance = klass.new
    sclass = instance.singleton_class
    meta = klass.singleton_class
    assert_kind_of(meta, sclass)
    assert_include(ObjectSpace.each_object(meta).to_a, sclass)
  end
end
