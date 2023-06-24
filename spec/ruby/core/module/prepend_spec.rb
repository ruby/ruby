require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module#prepend" do
  it "is a public method" do
    Module.should have_public_instance_method(:prepend, false)
  end

  it "does not affect the superclass" do
    Class.new { prepend Module.new }.superclass.should == Object
  end

  it "calls #prepend_features(self) in reversed order on each module" do
    ScratchPad.record []

    m = Module.new do
      def self.prepend_features(mod)
        ScratchPad << [ self, mod ]
      end
    end

    m2 = Module.new do
      def self.prepend_features(mod)
        ScratchPad << [ self, mod ]
      end
    end

    m3 = Module.new do
      def self.prepend_features(mod)
        ScratchPad << [ self, mod ]
      end
    end

    c = Class.new { prepend(m, m2, m3) }

    ScratchPad.recorded.should == [ [ m3, c], [ m2, c ], [ m, c ] ]
  end

  it "updates the method when a module is prepended" do
    m_module = Module.new do
      def foo
        "m"
      end
    end
    a_class = Class.new do
      def foo
        'a'
      end
    end
    a = a_class.new
    foo = -> { a.foo }
    foo.call.should == 'a'
    a_class.class_eval do
      prepend m_module
    end
    foo.call.should == 'm'
  end

  it "updates the method when a prepended module is updated" do
    m_module = Module.new
    a_class = Class.new do
      prepend m_module
      def foo
        'a'
      end
    end
    a = a_class.new
    foo = -> { a.foo }
    foo.call.should == 'a'
    m_module.module_eval do
      def foo
        "m"
      end
    end
    foo.call.should == 'm'
  end

  it "updates the method when there is a base included method and the prepended module overrides it" do
    base_module = Module.new do
      def foo
        'a'
      end
    end
    a_class = Class.new do
      include base_module
    end
    a = a_class.new
    foo = -> { a.foo }
    foo.call.should == 'a'

    m_module = Module.new do
      def foo
        "m"
      end
    end
    a_class.prepend m_module
    foo.call.should == 'm'
  end

  it "updates the method when there is a base included method and the prepended module is later updated" do
    base_module = Module.new do
      def foo
        'a'
      end
    end
    a_class = Class.new do
      include base_module
    end
    a = a_class.new
    foo = -> { a.foo }
    foo.call.should == 'a'

    m_module = Module.new
    a_class.prepend m_module
    foo.call.should == 'a'

    m_module.module_eval do
      def foo
        "m"
      end
    end
    foo.call.should == 'm'
  end

  it "updates the method when a module prepended after a call is later updated" do
    m_module = Module.new
    a_class = Class.new do
      def foo
        'a'
      end
    end
    a = a_class.new
    foo = -> { a.foo }
    foo.call.should == 'a'

    a_class.prepend m_module
    foo.call.should == 'a'

    m_module.module_eval do
      def foo
        "m"
      end
    end
    foo.call.should == 'm'
  end

  it "updates the method when a module is prepended after another and the method is defined later on that module" do
    m_module = Module.new do
      def foo
        'a'
      end
    end
    a_class = Class.new
    a_class.prepend m_module
    a = a_class.new
    foo = -> { a.foo }
    foo.call.should == 'a'

    n_module = Module.new
    a_class.prepend n_module
    foo.call.should == 'a'

    n_module.module_eval do
      def foo
        "n"
      end
    end
    foo.call.should == 'n'
  end

  it "updates the method when a module is included in a prepended module and the method is defined later" do
    a_class = Class.new
    base_module = Module.new do
      def foo
        'a'
      end
    end
    a_class.prepend base_module
    a = a_class.new
    foo = -> { a.foo }
    foo.call.should == 'a'

    m_module = Module.new
    n_module = Module.new
    m_module.include n_module
    a_class.prepend m_module

    n_module.module_eval do
      def foo
        "n"
      end
    end
    foo.call.should == 'n'
  end

  it "updates the method when a new module with an included module is prepended" do
    a_class = Class.new do
      def foo
        'a'
      end
    end

    n_module = Module.new do
      def foo
        'n'
      end
    end

    m_module = Module.new  do
      include n_module
    end

    a = a_class.new
    foo = -> { a.foo }

    foo.call.should == 'a'

    a_class.class_eval do
      prepend m_module
    end

    foo.call.should == 'n'
  end

  it "updates the constant when a module is prepended" do
    module ModuleSpecs::ConstUpdatePrepended
      module M
        FOO = 'm'
      end
      module A
        FOO = 'a'
      end
      module B
        include A
        def self.foo
          FOO
        end
      end

      B.foo.should == 'a'
      B.prepend M
      B.foo.should == 'm'
    end
  end

  it "updates the constant when a prepended module is updated" do
    module ModuleSpecs::ConstPrependedUpdated
      module M
      end
      module A
        FOO = 'a'
      end
      module B
        include A
        prepend M
        def self.foo
          FOO
        end
      end
      B.foo.should == 'a'
      M.const_set(:FOO, 'm')
      B.foo.should == 'm'
    end
  end

  it "updates the constant when there is a base included constant and the prepended module overrides it" do
    module ModuleSpecs::ConstIncludedPrependedOverride
      module Base
        FOO = 'a'
      end
      module A
        include Base
        def self.foo
          FOO
        end
      end
      A.foo.should == 'a'

      module M
        FOO = 'm'
      end
      A.prepend M
      A.foo.should == 'm'
    end
  end

  it "updates the constant when there is a base included constant and the prepended module is later updated" do
    module ModuleSpecs::ConstIncludedPrependedLaterUpdated
      module Base
        FOO = 'a'
      end
      module A
        include Base
        def self.foo
          FOO
        end
      end
      A.foo.should == 'a'

      module M
      end
      A.prepend M
      A.foo.should == 'a'

      M.const_set(:FOO, 'm')
      A.foo.should == 'm'
    end
  end

  it "updates the constant when a module prepended after a constant is later updated" do
    module ModuleSpecs::ConstUpdatedPrependedAfterLaterUpdated
      module M
      end
      module A
        FOO = 'a'
      end
      module B
        include A
        def self.foo
          FOO
        end
      end
      B.foo.should == 'a'

      B.prepend M
      B.foo.should == 'a'

      M.const_set(:FOO, 'm')
      B.foo.should == 'm'
    end
  end

  it "updates the constant when a module is prepended after another and the constant is defined later on that module" do
    module ModuleSpecs::ConstUpdatedPrependedAfterConstDefined
      module M
        FOO = 'm'
      end
      module A
        prepend M
        def self.foo
          FOO
        end
      end

      A.foo.should == 'm'

      module N
      end
      A.prepend N
      A.foo.should == 'm'

      N.const_set(:FOO, 'n')
      A.foo.should == 'n'
    end
  end

  it "updates the constant when a module is included in a prepended module and the constant is defined later" do
    module ModuleSpecs::ConstUpdatedIncludedInPrependedConstDefinedLater
      module A
        def self.foo
          FOO
        end
      end
      module Base
        FOO = 'a'
      end

      A.prepend Base
      A.foo.should == 'a'

      module N
      end
      module M
        include N
      end

      A.prepend M

      N.const_set(:FOO, 'n')
      A.foo.should == 'n'
    end
  end

  it "updates the constant when a new module with an included module is prepended" do
    module ModuleSpecs::ConstUpdatedNewModuleIncludedPrepended
      module A
        FOO = 'a'
      end
      module B
        include A
        def self.foo
          FOO
        end
      end
      module N
        FOO = 'n'
      end

      module M
        include N
      end

      B.foo.should == 'a'

      B.prepend M
      B.foo.should == 'n'
    end
  end

  it "raises a TypeError when the argument is not a Module" do
    -> { ModuleSpecs::Basic.prepend(Class.new) }.should raise_error(TypeError)
  end

  it "does not raise a TypeError when the argument is an instance of a subclass of Module" do
    -> { ModuleSpecs::SubclassSpec.prepend(ModuleSpecs::Subclass.new) }.should_not raise_error(TypeError)
  end

  it "imports constants" do
    m1 = Module.new
    m1::MY_CONSTANT = 1
    m2 = Module.new { prepend(m1) }
    m2.constants.should include(:MY_CONSTANT)
  end

  it "imports instance methods" do
    Module.new { prepend ModuleSpecs::A }.instance_methods.should include(:ma)
  end

  it "does not import methods to modules and classes" do
    Module.new { prepend ModuleSpecs::A }.methods.should_not include(:ma)
  end

  it "allows wrapping methods" do
    m = Module.new { def calc(x) super + 3 end }
    c = Class.new { def calc(x) x*2 end }
    c.prepend(m)
    c.new.calc(1).should == 5
  end

  it "also prepends included modules" do
    a = Module.new { def calc(x) x end }
    b = Module.new { include a }
    c = Class.new { prepend b }
    c.new.calc(1).should == 1
  end

  it "prepends multiple modules in the right order" do
    m1 = Module.new { def chain; super << :m1; end }
    m2 = Module.new { def chain; super << :m2; end; prepend(m1) }
    c = Class.new { def chain; [:c]; end; prepend(m2) }
    c.new.chain.should == [:c, :m2, :m1]
  end

  it "includes prepended modules in ancestors" do
    m = Module.new
    Class.new { prepend(m) }.ancestors.should include(m)
  end

  it "reports the prepended module as the method owner" do
    m = Module.new { def meth; end }
    c = Class.new { def meth; end; prepend(m) }
    c.new.method(:meth).owner.should == m
  end

  it "reports the prepended module as the unbound method owner" do
    m = Module.new { def meth; end }
    c = Class.new { def meth; end; prepend(m) }
    c.instance_method(:meth).owner.should == m
    c.public_instance_method(:meth).owner.should == m
  end

  it "causes the prepended module's method to be aliased by alias_method" do
    m = Module.new { def meth; :m end }
    c = Class.new { def meth; :c end; prepend(m); alias_method :alias, :meth }
    c.new.alias.should == :m
  end

  it "reports the class for the owner of an aliased method on the class" do
    m = Module.new
    c = Class.new { prepend(m); def meth; :c end; alias_method :alias, :meth }
    c.instance_method(:alias).owner.should == c
  end

  it "reports the class for the owner of a method aliased from the prepended module" do
    m = Module.new { def meth; :m end }
    c = Class.new { prepend(m); alias_method :alias, :meth }
    c.instance_method(:alias).owner.should == c
  end

  it "sees an instance of a prepended class as kind of the prepended module" do
    m = Module.new
    c = Class.new { prepend(m) }
    c.new.should be_kind_of(m)
  end

  it "keeps the module in the chain when dupping the class" do
    m = Module.new
    c = Class.new { prepend(m) }
    c.dup.new.should be_kind_of(m)
  end

  ruby_version_is ''...'3.0' do
    it "keeps the module in the chain when dupping an intermediate module" do
      m1 = Module.new { def calc(x) x end }
      m2 = Module.new { prepend(m1) }
      c1 = Class.new { prepend(m2) }
      m2dup = m2.dup
      m2dup.ancestors.should == [m2dup,m1,m2]
      c2 = Class.new { prepend(m2dup) }
      c1.ancestors[0,3].should == [m1,m2,c1]
      c1.new.should be_kind_of(m1)
      c2.ancestors[0,4].should == [m2dup,m1,m2,c2]
      c2.new.should be_kind_of(m1)
    end
  end

  ruby_version_is '3.0' do
    it "uses only new module when dupping the module" do
      m1 = Module.new { def calc(x) x end }
      m2 = Module.new { prepend(m1) }
      c1 = Class.new { prepend(m2) }
      m2dup = m2.dup
      m2dup.ancestors.should == [m1,m2dup]
      c2 = Class.new { prepend(m2dup) }
      c1.ancestors[0,3].should == [m1,m2,c1]
      c1.new.should be_kind_of(m1)
      c2.ancestors[0,3].should == [m1,m2dup,c2]
      c2.new.should be_kind_of(m1)
    end
  end

  it "depends on prepend_features to add the module" do
    m = Module.new { def self.prepend_features(mod) end }
    Class.new { prepend(m) }.ancestors.should_not include(m)
  end

  it "adds the module in the subclass chains" do
    parent = Class.new { def chain; [:parent]; end }
    child = Class.new(parent) { def chain; super << :child; end }
    mod = Module.new { def chain; super << :mod; end }
    parent.prepend(mod)
    parent.ancestors[0,2].should == [mod, parent]
    child.ancestors[0,3].should == [child, mod, parent]

    parent.new.chain.should == [:parent, :mod]
    child.new.chain.should == [:parent, :mod, :child]
  end

  it "inserts a later prepended module into the chain" do
    m1 = Module.new { def chain; super << :m1; end }
    m2 = Module.new { def chain; super << :m2; end }
    c1 = Class.new { def chain; [:c1]; end; prepend m1 }
    c2 = Class.new(c1) { def chain; super << :c2; end }
    c2.new.chain.should == [:c1, :m1, :c2]
    c1.prepend(m2)
    c2.new.chain.should == [:c1, :m1, :m2, :c2]
  end

  it "works with subclasses" do
    m = Module.new do
      def chain
        super << :module
      end
    end

    c = Class.new do
      prepend m
      def chain
        [:class]
      end
    end

    s = Class.new(c) do
      def chain
        super << :subclass
      end
    end

    s.new.chain.should == [:class, :module, :subclass]
  end

  it "throws a NoMethodError when there is no more superclass" do
    m = Module.new do
      def chain
        super << :module
      end
    end

    c = Class.new do
      prepend m
      def chain
        super << :class
      end
    end
    -> { c.new.chain }.should raise_error(NoMethodError)
  end

  it "calls prepended after prepend_features" do
    ScratchPad.record []

    m = Module.new do
      def self.prepend_features(klass)
        ScratchPad << [:prepend_features, klass]
      end
      def self.prepended(klass)
        ScratchPad << [:prepended, klass]
      end
    end

    c = Class.new { prepend(m) }
    ScratchPad.recorded.should == [[:prepend_features, c], [:prepended, c]]
  end

  it "prepends a module if it is included in a super class" do
    module ModuleSpecs::M3
      module M; end
      class A; include M; end
      class B < A; prepend M; end

      all = [A, B, M]

      (B.ancestors.filter { |a| all.include?(a) }).should == [M, B, A, M]
    end
  end

  it "detects cyclic prepends" do
    -> {
      module ModuleSpecs::P
        prepend ModuleSpecs::P
      end
    }.should raise_error(ArgumentError)
  end

  it "doesn't accept no-arguments" do
    -> {
      Module.new do
        prepend
      end
    }.should raise_error(ArgumentError)
  end

  it "returns the class it's included into" do
    m = Module.new
    r = nil
    c = Class.new { r = prepend m }
    r.should == c
  end

  it "clears any caches" do
    module ModuleSpecs::M3
      module PM1
        def foo
          :m1
        end
      end

      module PM2
        def foo
          :m2
        end
      end

      klass = Class.new do
        prepend PM1

        def get
          foo
        end
      end

      o = klass.new
      o.get.should == :m1

      klass.class_eval do
        prepend PM2
      end

      o.get.should == :m2
    end
  end

  it "supports super when the module is prepended into a singleton class" do
    ScratchPad.record []

    mod = Module.new do
      def self.inherited(base)
        super
      end
    end

    module_with_singleton_class_prepend = Module.new do
      singleton_class.prepend(mod)
    end

    klass = Class.new(ModuleSpecs::RecordIncludedModules) do
      include module_with_singleton_class_prepend
    end

    ScratchPad.recorded.should == klass
  end

  it "supports super when the module is prepended into a singleton class with a class super" do
    ScratchPad.record []

    base_class = Class.new(ModuleSpecs::RecordIncludedModules) do
      def self.inherited(base)
        super
      end
    end

    prepended_module = Module.new
    base_class.singleton_class.prepend(prepended_module)

    child_class = Class.new(base_class)
    ScratchPad.recorded.should == child_class
  end

  it "does not interfere with a define_method super in the original class" do
    base_class = Class.new do
      def foo(ary)
        ary << 1
      end
    end

    child_class = Class.new(base_class) do
      define_method :foo do |ary|
        ary << 2
        super(ary)
      end
    end

    prep_mod = Module.new do
      def foo(ary)
        ary << 3
        super(ary)
      end
    end

    child_class.prepend(prep_mod)

    ary = []
    child_class.new.foo(ary)
    ary.should == [3, 2, 1]
  end

  describe "called on a module" do
    describe "included into a class"
    it "does not obscure the module's methods from reflective access" do
      mod = Module.new do
        def foo; end
      end
      cls = Class.new do
        include mod
      end
      pre = Module.new
      mod.prepend pre

      cls.instance_methods.should include(:foo)
    end
  end
end
