require_relative '../spec_helper'
require_relative 'fixtures/super'

describe "The super keyword" do
  it "calls the method on the calling class" do
    SuperSpecs::S1::A.new.foo([]).should == ["A#foo","A#bar"]
    SuperSpecs::S1::A.new.bar([]).should == ["A#bar"]
    SuperSpecs::S1::B.new.foo([]).should == ["B#foo","A#foo","B#bar","A#bar"]
    SuperSpecs::S1::B.new.bar([]).should == ["B#bar","A#bar"]
  end

  it "searches the full inheritance chain" do
    SuperSpecs::S2::B.new.foo([]).should == ["B#foo","A#baz"]
    SuperSpecs::S2::B.new.baz([]).should == ["A#baz"]
    SuperSpecs::S2::C.new.foo([]).should == ["B#foo","C#baz","A#baz"]
    SuperSpecs::S2::C.new.baz([]).should == ["C#baz","A#baz"]
  end

  it "searches class methods" do
    SuperSpecs::S3::A.new.foo([]).should == ["A#foo"]
    SuperSpecs::S3::A.foo([]).should == ["A.foo"]
    SuperSpecs::S3::A.bar([]).should == ["A.bar","A.foo"]
    SuperSpecs::S3::B.new.foo([]).should == ["A#foo"]
    SuperSpecs::S3::B.foo([]).should == ["B.foo","A.foo"]
    SuperSpecs::S3::B.bar([]).should == ["B.bar","A.bar","B.foo","A.foo"]
  end

  it "calls the method on the calling class including modules" do
    SuperSpecs::MS1::A.new.foo([]).should == ["ModA#foo","ModA#bar"]
    SuperSpecs::MS1::A.new.bar([]).should == ["ModA#bar"]
    SuperSpecs::MS1::B.new.foo([]).should == ["B#foo","ModA#foo","ModB#bar","ModA#bar"]
    SuperSpecs::MS1::B.new.bar([]).should == ["ModB#bar","ModA#bar"]
  end

  it "searches the full inheritance chain including modules" do
    SuperSpecs::MS2::B.new.foo([]).should == ["ModB#foo","A#baz"]
    SuperSpecs::MS2::B.new.baz([]).should == ["A#baz"]
    SuperSpecs::MS2::C.new.baz([]).should == ["C#baz","A#baz"]
    SuperSpecs::MS2::C.new.foo([]).should == ["ModB#foo","C#baz","A#baz"]
  end

  it "can resolve to different methods in an included module method" do
    SuperSpecs::MultiSuperTargets::A.new.foo.should == :BaseA
    SuperSpecs::MultiSuperTargets::B.new.foo.should == :BaseB
  end

  it "searches class methods including modules" do
    SuperSpecs::MS3::A.new.foo([]).should == ["A#foo"]
    SuperSpecs::MS3::A.foo([]).should == ["ModA#foo"]
    SuperSpecs::MS3::A.bar([]).should == ["ModA#bar","ModA#foo"]
    SuperSpecs::MS3::B.new.foo([]).should == ["A#foo"]
    SuperSpecs::MS3::B.foo([]).should == ["B.foo","ModA#foo"]
    SuperSpecs::MS3::B.bar([]).should == ["B.bar","ModA#bar","B.foo","ModA#foo"]
  end

  it "searches BasicObject from a module for methods defined there" do
    SuperSpecs::IncludesFromBasic.new.__send__(:foobar).should == 43
  end

  it "searches BasicObject through another module for methods defined there" do
    SuperSpecs::IncludesIntermediate.new.__send__(:foobar).should == 42
  end

  it "calls the correct method when the method visibility is modified" do
    SuperSpecs::MS4::A.new.example.should == 5
  end

  it "calls the correct method when the superclass argument list is different from the subclass" do
    SuperSpecs::S4::A.new.foo([]).should == ["A#foo"]
    SuperSpecs::S4::B.new.foo([],"test").should == ["B#foo(a,test)", "A#foo"]
  end

  it "raises an error error when super method does not exist" do
    sup = Class.new
    sub_normal = Class.new(sup) do
      def foo
        super()
      end
    end
    sub_zsuper = Class.new(sup) do
      def foo
        super
      end
    end

    -> {sub_normal.new.foo}.should raise_error(NoMethodError, /super/)
    -> {sub_zsuper.new.foo}.should raise_error(NoMethodError, /super/)
  end

  it "uses given block even if arguments are passed explicitly" do
    c1 = Class.new do
      def m
        yield
      end
    end
    c2 = Class.new(c1) do
      def m(v)
        super()
      end
    end

    c2.new.m(:dump) { :value }.should == :value
  end

  it "can pass an explicit block" do
    c1 = Class.new do
      def m(v)
        yield(v)
      end
    end
    c2 = Class.new(c1) do
      def m(v)
        block = -> w { yield(w + 'b') }
        super(v, &block)
      end
    end

    c2.new.m('a') { |x| x + 'c' }.should == 'abc'
  end

  it "can pass no block using &nil" do
    c1 = Class.new do
      def m(v)
        block_given?
      end
    end
    c2 = Class.new(c1) do
      def m(v)
        super(v, &nil)
      end
    end

    c2.new.m('a') { raise }.should be_false
  end

  it "uses block argument given to method when used in a block" do
    c1 = Class.new do
      def m
        yield
      end
    end
    c2 = Class.new(c1) do
      def m(v)
        ary = []
        1.times do
          ary << super()
        end
        ary
      end
    end

    c2.new.m(:dump) { :value }.should == [ :value ]
  end

  it "calls the superclass method when in a block" do
    SuperSpecs::S6.new.here.should == :good
  end

  it "calls the superclass method when initial method is defined_method'd" do
    SuperSpecs::S7.new.here.should == :good
  end

  it "can call through a define_method multiple times (caching check)" do
    obj = SuperSpecs::S7.new

    2.times do
      obj.here.should == :good
    end
  end

  it "supers up appropriate name even if used for multiple method names" do
    sup = Class.new do
      def a; "a"; end
      def b; "b"; end
    end

    sub = Class.new(sup) do
      [:a, :b].each do |name|
        define_method name do
          super()
        end
      end
    end

    sub.new.a.should == "a"
    sub.new.b.should == "b"
    sub.new.a.should == "a"
  end

  it "raises a RuntimeError when called with implicit arguments from a method defined with define_method" do
    super_class = Class.new do
      def a(arg)
        arg
      end
    end

    klass = Class.new super_class do
      define_method :a do |arg|
        super
      end
    end

    -> { klass.new.a(:a_called) }.should raise_error(RuntimeError)
  end

  it "is able to navigate to super, when a method is defined dynamically on the singleton class" do
    foo_class = Class.new do
      def bar
        "bar"
      end
    end

    mixin_module = Module.new do
      def bar
        "super_" + super
      end
    end

    foo = foo_class.new
    foo.singleton_class.define_method(:bar, mixin_module.instance_method(:bar))

    foo.bar.should == "super_bar"
  end

  # Rubinius ticket github#157
  it "calls method_missing when a superclass method is not found" do
    SuperSpecs::MM_B.new.is_a?(Hash).should == false
  end

  # Rubinius ticket github#180
  it "respects the original module a method is aliased from" do
    SuperSpecs::Alias3.new.name3.should == [:alias2, :alias1]
  end

  it "sees the included version of a module a method is alias from" do
    SuperSpecs::AliasWithSuper::Trigger.foo.should == [:b, :a]
  end

  it "find super from a singleton class" do
    obj = SuperSpecs::SingletonCase::Foo.new
    def obj.foobar(array)
      array << :singleton
      super
    end
    obj.foobar([]).should == [:singleton, :foo, :base]
  end

  it "finds super on other objects if a singleton class aliased the method" do
    orig_obj = SuperSpecs::SingletonAliasCase::Foo.new
    orig_obj.alias_on_singleton
    orig_obj.new_foobar([]).should == [:foo, :base]
    SuperSpecs::SingletonAliasCase::Foo.new.foobar([]).should == [:foo, :base]
  end

  it "passes along modified rest args when they weren't originally empty" do
    SuperSpecs::RestArgsWithSuper::B.new.a("bar").should == ["bar", "foo"]
  end

  it "passes along modified rest args when they were originally empty" do
    SuperSpecs::RestArgsWithSuper::B.new.a.should == ["foo"]
  end

  # https://bugs.ruby-lang.org/issues/14279
  it "passes along reassigned rest args" do
    SuperSpecs::ZSuperWithRestReassigned::B.new.a("bar").should == ["foo"]
  end

  # https://bugs.ruby-lang.org/issues/14279
  it "wraps into array and passes along reassigned rest args with non-array scalar value" do
    SuperSpecs::ZSuperWithRestReassignedWithScalar::B.new.a("bar").should == ["foo"]
  end

  it "invokes methods from a chain of anonymous modules" do
    SuperSpecs::AnonymousModuleIncludedTwice.new.a([]).should == ["anon", "anon", "non-anon"]
  end

  it "without explicit arguments can accept a block but still pass the original arguments" do
    SuperSpecs::ZSuperWithBlock::B.new.a.should == 14
  end

  it "passes along block via reference to method expecting a reference" do
    SuperSpecs::ZSuperWithBlock::B.new.b.should == [14, 15]
  end

  it "passes along a block via reference to a method that yields" do
    SuperSpecs::ZSuperWithBlock::B.new.c.should == 16
  end

  it "without explicit arguments passes optional arguments that have a default value" do
    SuperSpecs::ZSuperWithOptional::B.new.m(1, 2).should == 14
  end

  it "without explicit arguments passes optional arguments that have a non-default value" do
    SuperSpecs::ZSuperWithOptional::B.new.m(1, 2, 3).should == 3
  end

  it "without explicit arguments passes optional arguments that have a default value but were modified" do
    SuperSpecs::ZSuperWithOptional::C.new.m(1, 2).should == 100
  end

  it "without explicit arguments passes optional arguments that have a non-default value but were modified" do
    SuperSpecs::ZSuperWithOptional::C.new.m(1, 2, 3).should == 100
  end

  it "without explicit arguments passes rest arguments" do
    SuperSpecs::ZSuperWithRest::B.new.m(1, 2, 3).should == [1, 2, 3]
  end

  it "without explicit arguments passes rest arguments including any modifications" do
    SuperSpecs::ZSuperWithRest::B.new.m_modified(1, 2, 3).should == [1, 14, 3]
  end

  it "without explicit arguments passes arguments and rest arguments" do
    SuperSpecs::ZSuperWithRestAndOthers::B.new.m(1, 2, 3, 4, 5).should == [3, 4, 5]
    SuperSpecs::ZSuperWithRestAndOthers::B.new.m(1, 2).should == []
  end

  it "without explicit arguments passes arguments, rest arguments, and post arguments" do
    SuperSpecs::ZSuperWithRestAndPost::B.new.m(1, 2, 3, 4, 5).should == [1, 2, 3]
    SuperSpecs::ZSuperWithRestOthersAndPost::B.new.m(1, 2, 3, 4, 5).should == [2, 3, 4]
    SuperSpecs::ZSuperWithRestAndPost::B.new.m(1, 2).should == []
    SuperSpecs::ZSuperWithRestOthersAndPost::B.new.m(1, 2).should == []
  end

  it "without explicit arguments passes arguments, rest arguments including modifications, and post arguments" do
    SuperSpecs::ZSuperWithRestAndPost::B.new.m_modified(1, 2, 3, 4, 5).should == [1, 14, 3]
    SuperSpecs::ZSuperWithRestOthersAndPost::B.new.m_modified(1, 2, 3, 4, 5).should == [2, 14, 4]
    SuperSpecs::ZSuperWithRestAndPost::B.new.m_modified(1, 2).should == [nil, 14]
    SuperSpecs::ZSuperWithRestOthersAndPost::B.new.m_modified(1, 2).should == [nil, 14]
  end

  it "without explicit arguments passes arguments and rest arguments including any modifications" do
    SuperSpecs::ZSuperWithRestAndOthers::B.new.m_modified(1, 2, 3, 4, 5).should == [3, 14, 5]
  end

  it "without explicit arguments that are '_'" do
    SuperSpecs::ZSuperWithUnderscores::B.new.m(1, 2).should == [1, 2]
  end

  it "without explicit arguments that are '_' including any modifications" do
    SuperSpecs::ZSuperWithUnderscores::B.new.m_modified(1, 2).should == [14, 2]
  end

  it "should pass method arguments when called within a closure" do
    SuperSpecs::ZSuperInBlock::B.new.m(arg: 1).should == 1
  end

  describe 'when using keyword arguments' do
    before :each do
      @req  = SuperSpecs::Keywords::RequiredArguments.new
      @opts = SuperSpecs::Keywords::OptionalArguments.new
      @etc  = SuperSpecs::Keywords::PlaceholderArguments.new

      @req_and_opts = SuperSpecs::Keywords::RequiredAndOptionalArguments.new
      @req_and_etc  = SuperSpecs::Keywords::RequiredAndPlaceholderArguments.new
      @opts_and_etc = SuperSpecs::Keywords::OptionalAndPlaceholderArguments.new

      @req_and_opts_and_etc = SuperSpecs::Keywords::RequiredAndOptionalAndPlaceholderArguments.new
    end

    it 'does not pass any arguments to the parent when none are given' do
      @etc.foo.should == {}
    end

    it 'passes only required arguments to the parent when no optional arguments are given' do
      [@req, @req_and_etc].each do |obj|
        obj.foo(a: 'a').should == {a: 'a'}
      end
    end

    it 'passes default argument values to the parent' do
      [@opts, @opts_and_etc].each do |obj|
        obj.foo.should == {b: 'b'}
      end

      [@req_and_opts, @opts_and_etc, @req_and_opts_and_etc].each do |obj|
        obj.foo(a: 'a').should == {a: 'a', b: 'b'}
      end
    end

    it 'passes any given arguments including optional keyword arguments to the parent' do
      [@etc, @req_and_opts, @req_and_etc, @opts_and_etc, @req_and_opts_and_etc].each do |obj|
        obj.foo(a: 'a', b: 'b').should == {a: 'a', b: 'b'}
      end

      [@etc, @req_and_etc, @opts_and_etc, @req_and_opts_and_etc].each do |obj|
        obj.foo(a: 'a', b: 'b', c: 'c').should == {a: 'a', b: 'b', c: 'c'}
      end
    end
  end

  describe 'when using regular and keyword arguments' do
    before :each do
      @req  = SuperSpecs::RegularAndKeywords::RequiredArguments.new
      @opts = SuperSpecs::RegularAndKeywords::OptionalArguments.new
      @etc  = SuperSpecs::RegularAndKeywords::PlaceholderArguments.new

      @req_and_opts = SuperSpecs::RegularAndKeywords::RequiredAndOptionalArguments.new
      @req_and_etc  = SuperSpecs::RegularAndKeywords::RequiredAndPlaceholderArguments.new
      @opts_and_etc = SuperSpecs::RegularAndKeywords::OptionalAndPlaceholderArguments.new

      @req_and_opts_and_etc = SuperSpecs::RegularAndKeywords::RequiredAndOptionalAndPlaceholderArguments.new
    end

    it 'passes only required regular arguments to the parent when no optional keyword arguments are given' do
      @etc.foo('a').should == ['a', {}]
    end

    it 'passes only required regular and keyword arguments to the parent when no optional keyword arguments are given' do
      [@req, @req_and_etc].each do |obj|
        obj.foo('a', b: 'b').should == ['a', {b: 'b'}]
      end
    end

    it 'passes default argument values to the parent' do
      [@opts, @opts_and_etc].each do |obj|
        obj.foo('a').should == ['a', {c: 'c'}]
      end

      [@req_and_opts, @opts_and_etc, @req_and_opts_and_etc].each do |obj|
        obj.foo('a', b: 'b').should == ['a', {b: 'b', c: 'c'}]
      end
    end

    it 'passes any given regular and keyword arguments including optional keyword arguments to the parent' do
      [@etc, @req_and_opts, @req_and_etc, @opts_and_etc, @req_and_opts_and_etc].each do |obj|
        obj.foo('a', b: 'b', c: 'c').should == ['a', {b: 'b', c: 'c'}]
      end

      [@etc, @req_and_etc, @opts_and_etc, @req_and_opts_and_etc].each do |obj|
        obj.foo('a', b: 'b', c: 'c', d: 'd').should == ['a', {b: 'b', c: 'c', d: 'd'}]
      end
    end
  end

  describe 'when using splat and keyword arguments' do
    before :each do
      @all = SuperSpecs::SplatAndKeywords::AllArguments.new
    end

    it 'does not pass any arguments to the parent when none are given' do
      @all.foo.should == [[], {}]
    end

    it 'passes only splat arguments to the parent when no keyword arguments are given' do
      @all.foo('a').should == [['a'], {}]
    end

    it 'passes only keyword arguments to the parent when no splat arguments are given' do
      @all.foo(b: 'b').should == [[], {b: 'b'}]
    end

    it 'passes any given splat and keyword arguments to the parent' do
      @all.foo('a', b: 'b').should == [['a'], {b: 'b'}]
    end
  end
end
