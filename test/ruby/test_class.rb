require 'test/unit'

class TestClass < Test::Unit::TestCase
  # ------------------
  # Various test classes
  # ------------------

  class ClassOne
    attr :num_args
    @@subs = []
    def initialize(*args)
      @num_args = args.size
      @args = args
    end
    def [](n)
      @args[n]
    end
    def ClassOne.inherited(klass)
      @@subs.push klass
    end
    def subs
      @@subs
    end
  end

  class ClassTwo < ClassOne
  end

  class ClassThree < ClassOne
  end

  class ClassFour < ClassThree
  end

  # ------------------
  # Start of tests
  # ------------------

  def test_s_inherited
    assert_equal([ClassTwo, ClassThree, ClassFour], ClassOne.new.subs)
  end

  def test_s_new
    c = Class.new
    assert_same(Class, c.class)
    assert_same(Object, c.superclass)

    c = Class.new(Fixnum)
    assert_same(Class, c.class)
    assert_same(Fixnum, c.superclass)
  end

  def test_00_new_basic
    a = ClassOne.new
    assert_equal(ClassOne, a.class)
    assert_equal(0, a.num_args)

    a = ClassOne.new(1, 2, 3)
    assert_equal(3, a.num_args)
    assert_equal(1, a[0])
  end

  def test_01_new_inherited
    a = ClassTwo.new
    assert_equal(ClassTwo, a.class)
    assert_equal(0, a.num_args)

    a = ClassTwo.new(1, 2, 3)
    assert_equal(3, a.num_args)
    assert_equal(1, a[0])
  end

  def test_superclass
    assert_equal(ClassOne, ClassTwo.superclass)
    assert_equal(Object,   ClassTwo.superclass.superclass)
    assert_equal(BasicObject, ClassTwo.superclass.superclass.superclass)
  end

  def test_class_cmp
    assert_raise(TypeError) { Class.new <= 1 }
    assert_raise(TypeError) { Class.new >= 1 }
    assert_nil(Class.new <=> 1)
  end

  def test_class_initialize
    assert_raise(TypeError) do
      Class.new.instance_eval { initialize }
    end
  end

  def test_instanciate_singleton_class
    c = class << Object.new; self; end
    assert_raise(TypeError) { c.new }
  end

  def test_superclass_of_basicobject
    assert_equal(nil, BasicObject.superclass)
  end

  def test_module_function
    c = Class.new
    assert_raise(TypeError) do
      Module.instance_method(:module_function).bind(c).call(:foo)
    end
  end

  def test_extend_object
    c = Class.new
    assert_raise(TypeError) do
      Module.instance_method(:extend_object).bind(c).call(Object.new)
    end
  end

  def test_append_features
    c = Class.new
    assert_raise(TypeError) do
      Module.instance_method(:append_features).bind(c).call(Module.new)
    end
  end

  def test_prepend_features
    c = Class.new
    assert_raise(TypeError) do
      Module.instance_method(:prepend_features).bind(c).call(Module.new)
    end
  end

  def test_module_specific_methods
    assert_empty(Class.private_instance_methods(true) &
      [:module_function, :extend_object, :append_features, :prepend_features])
  end

  def test_method_redefinition
    feature2155 = '[ruby-dev:39400]'

    line = __LINE__+4
    stderr = EnvUtil.verbose_warning do
      Class.new do
        def foo; end
        def foo; end
      end
    end
    assert_match(/:#{line}: warning: method redefined; discarding old foo/, stderr)
    assert_match(/:#{line-1}: warning: previous definition of foo/, stderr, feature2155)

    assert_warning '' do
      Class.new do
        def foo; end
        alias bar foo
        def foo; end
      end
    end

    assert_warning '' do
      Class.new do
        def foo; end
        alias bar foo
        alias bar foo
      end
    end

    line = __LINE__+4
    stderr = EnvUtil.verbose_warning do
      Class.new do
        define_method(:foo) do end
        def foo; end
      end
    end
    assert_match(/:#{line}: warning: method redefined; discarding old foo/, stderr)
    assert_match(/:#{line-1}: warning: previous definition of foo/, stderr, feature2155)

    assert_warning '' do
      Class.new do
        define_method(:foo) do end
        alias bar foo
        alias bar foo
      end
    end

    assert_warning '' do
      Class.new do
        def foo; end
        undef foo
      end
    end
  end

  def test_check_inheritable
    assert_raise(TypeError) { Class.new(Object.new) }

    o = Object.new
    c = class << o; self; end
    assert_raise(TypeError) { Class.new(c) }
    assert_raise(TypeError) { Class.new(Class) }
    assert_raise(TypeError) { eval("class Foo < Class; end") }
  end

  def test_initialize_copy
    c = Class.new
    assert_raise(TypeError) { c.instance_eval { initialize_copy(1) } }

    o = Object.new
    c = class << o; self; end
    assert_raise(TypeError) { c.dup }

    assert_raise(TypeError) { BasicObject.dup }
  end

  def test_singleton_class
    assert_raise(TypeError) { 1.extend(Module.new) }
    assert_raise(TypeError) { 1.0.extend(Module.new) }
    assert_raise(TypeError) { (2.0**1000).extend(Module.new) }
    assert_raise(TypeError) { :foo.extend(Module.new) }

    assert_in_out_err([], <<-INPUT, %w(:foo :foo true true), [])
      module Foo; def foo; :foo; end; end
      false.extend(Foo)
      true.extend(Foo)
      p false.foo
      p true.foo
      p FalseClass.include?(Foo)
      p TrueClass.include?(Foo)
    INPUT
  end

  def test_uninitialized
    assert_raise(TypeError) { Class.allocate.new }
    assert_raise(TypeError) { Class.allocate.superclass }
    bug6863 = '[ruby-core:47148]'
    assert_raise(TypeError, bug6863) { Class.new(Class.allocate) }
  end

  def test_nonascii_name
    c = eval("class ::C\u{df}; self; end")
    assert_equal("C\u{df}", c.name, '[ruby-core:24600]')
    c = eval("class C\u{df}; self; end")
    assert_equal("TestClass::C\u{df}", c.name, '[ruby-core:24600]')
  end

  def test_invalid_jump_from_class_definition
    assert_raise(SyntaxError) { eval("class C; next; end") }
    assert_raise(SyntaxError) { eval("class C; break; end") }
    assert_raise(SyntaxError) { eval("class C; redo; end") }
    assert_raise(SyntaxError) { eval("class C; retry; end") }
    assert_raise(SyntaxError) { eval("class C; return; end") }
    assert_raise(SyntaxError) { eval("class C; yield; end") }
  end

  def test_clone
    original = Class.new {
      def foo
        return super()
      end
    }
    mod = Module.new {
      def foo
        return "mod#foo"
      end
    }
    copy = original.clone
    copy.send(:include, mod)
    assert_equal("mod#foo", copy.new.foo)
  end

  def test_nested_class_removal
    assert_normal_exit('File.__send__(:remove_const, :Stat); at_exit{File.stat(".")}; GC.start')
  end

  class PrivateClass
  end
  private_constant :PrivateClass

  def test_redefine_private_class
    assert_raise(NameError) do
      eval("class ::TestClass::PrivateClass; end")
    end
    eval <<-END
      class ::TestClass
        class PrivateClass
          def foo; 42; end
        end
      end
    END
    assert_equal(42, PrivateClass.new.foo)
  end

  StrClone = String.clone
  Class.new(StrClone)

  def test_cloned_class
    bug5274 = StrClone.new("[ruby-dev:44460]")
    assert_equal(bug5274, Marshal.load(Marshal.dump(bug5274)))
  end

  def test_cannot_reinitialize_class_with_initialize_copy # [ruby-core:50869]
    assert_in_out_err([], <<-'end;', ["Object"], [])
      class Class
        def initialize_copy(*); super; end
      end

      class A; end
      class B; end

      A.send(:initialize_copy, Class.new(B)) rescue nil

      p A.superclass
    end;
  end

  module M
    C = 1

    def self.m
      C
    end
  end

  def test_constant_access_from_method_in_cloned_module # [ruby-core:47834]
    m = M.dup
    assert_equal 1, m::C
    assert_equal 1, m.m
  end

  def test_invalid_superclass
    assert_raise(TypeError) do
      eval <<-'end;'
        class C < nil
        end
      end;
    end

    assert_raise(TypeError) do
      eval <<-'end;'
        class C < false
        end
      end;
    end

    assert_raise(TypeError) do
      eval <<-'end;'
        class C < true
        end
      end;
    end

    assert_raise(TypeError) do
      eval <<-'end;'
        class C < 0
        end
      end;
    end

    assert_raise(TypeError) do
      eval <<-'end;'
        class C < ""
        end
      end;
    end
  end

  def test_cloned_singleton_method_added
    bug5283 = '[ruby-dev:44477]'
    added = []
    c = Class.new
    c.singleton_class.class_eval do
      define_method(:singleton_method_added) {|mid| added << [self, mid]}
      def foo; :foo; end
    end
    added.clear
    d = c.clone
    assert_empty(added.grep(->(k) {c == k[0]}), bug5283)
    assert_equal(:foo, d.foo)
  end

  def test_singleton_class_p
    feature7609 = '[ruby-core:51087] [Feature #7609]'
    assert_predicate(self.singleton_class, :singleton_class?, feature7609)
    assert_not_predicate(self.class, :singleton_class?, feature7609)
  end

  def test_freeze_to_s
    assert_nothing_raised("[ruby-core:41858] [Bug #5828]") {
      Class.new.freeze.clone.to_s
    }
  end

  def test_singleton_class_of_frozen_object
    obj = Object.new
    c = obj.singleton_class
    obj.freeze
    assert_raise_with_message(RuntimeError, /frozen object/) {
      c.class_eval {def f; end}
    }
  end

  def test_singleton_class_message
    c = Class.new.freeze
    assert_raise_with_message(RuntimeError, /frozen Class/) {
      def c.f; end
    }
  end

  def test_singleton_class_should_has_own_namespace
    # CONST in singleton class
    objs = []
    $i = 0

    2.times{
      objs << obj = Object.new
      class << obj
        CONST = ($i += 1)
        def foo
          CONST
        end
      end
    }
    assert_equal(1, objs[0].foo, '[Bug #10943]')
    assert_equal(2, objs[1].foo, '[Bug #10943]')

    # CONST in block in singleton class
    objs = []
    $i = 0

    2.times{
      objs << obj = Object.new
      class << obj
        1.times{
          CONST = ($i += 1)
        }
        def foo
          [nil].map{
            CONST
          }
        end
      end
    }
    assert_equal([1], objs[0].foo, '[Bug #10943]')
    assert_equal([2], objs[1].foo, '[Bug #10943]')

    # class def in singleton class
    objs = []
    $xs = []
    $i = 0

    2.times{
      objs << obj = Object.new
      class << obj
        CONST = ($i += 1)
        class X
          $xs << self
          CONST = ($i += 1)
          def foo
            CONST
          end
        end

        def x
          X
        end
      end
    }
    assert_not_equal($xs[0], $xs[1], '[Bug #10943]')
    assert_not_equal(objs[0].x, objs[1].x, '[Bug #10943]')
    assert_equal(2, $xs[0]::CONST, '[Bug #10943]')
    assert_equal(2, $xs[0].new.foo, '[Bug #10943]')
    assert_equal(4, $xs[1]::CONST, '[Bug #10943]')
    assert_equal(4, $xs[1].new.foo, '[Bug #10943]')

    # class def in block in singleton class
    objs = []
    $xs = []
    $i = 0

    2.times{
      objs << obj = Object.new
      class << obj
        1.times{
          CONST = ($i += 1)
        }
        1.times{
          class X
            $xs << self
            CONST = ($i += 1)
            def foo
              CONST
            end
          end

          def x
            X
          end
        }
      end
    }
    assert_not_equal($xs[0], $xs[1], '[Bug #10943]')
    assert_not_equal(objs[0].x, objs[1].x, '[Bug #10943]')
    assert_equal(2, $xs[0]::CONST, '[Bug #10943]')
    assert_equal(2, $xs[0].new.foo, '[Bug #10943]')
    assert_equal(4, $xs[1]::CONST, '[Bug #10943]')
    assert_equal(4, $xs[1].new.foo, '[Bug #10943]')

    # method def in singleton class
    ms = []
    ps = $test_singleton_class_shared_cref_ps = []
    2.times{
      ms << Module.new do
        class << self
          $test_singleton_class_shared_cref_ps << Proc.new{
            def xyzzy
              self
            end
          }
        end
      end
    }

    ps.each{|p| p.call} # define xyzzy methods for each singleton classes
    ms.each{|m|
      assert_equal(m, m.xyzzy, "Bug #10871")
    }
  end
end
