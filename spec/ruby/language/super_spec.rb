require_relative '../spec_helper'
require_relative 'fixtures/super'

describe "The super keyword" do
  it "calls the method on the calling class" do
    Super::S1::A.new.foo([]).should == ["A#foo","A#bar"]
    Super::S1::A.new.bar([]).should == ["A#bar"]
    Super::S1::B.new.foo([]).should == ["B#foo","A#foo","B#bar","A#bar"]
    Super::S1::B.new.bar([]).should == ["B#bar","A#bar"]
  end

  it "searches the full inheritance chain" do
    Super::S2::B.new.foo([]).should == ["B#foo","A#baz"]
    Super::S2::B.new.baz([]).should == ["A#baz"]
    Super::S2::C.new.foo([]).should == ["B#foo","C#baz","A#baz"]
    Super::S2::C.new.baz([]).should == ["C#baz","A#baz"]
  end

  it "searches class methods" do
    Super::S3::A.new.foo([]).should == ["A#foo"]
    Super::S3::A.foo([]).should == ["A.foo"]
    Super::S3::A.bar([]).should == ["A.bar","A.foo"]
    Super::S3::B.new.foo([]).should == ["A#foo"]
    Super::S3::B.foo([]).should == ["B.foo","A.foo"]
    Super::S3::B.bar([]).should == ["B.bar","A.bar","B.foo","A.foo"]
  end

  it "calls the method on the calling class including modules" do
    Super::MS1::A.new.foo([]).should == ["ModA#foo","ModA#bar"]
    Super::MS1::A.new.bar([]).should == ["ModA#bar"]
    Super::MS1::B.new.foo([]).should == ["B#foo","ModA#foo","ModB#bar","ModA#bar"]
    Super::MS1::B.new.bar([]).should == ["ModB#bar","ModA#bar"]
  end

  it "searches the full inheritance chain including modules" do
    Super::MS2::B.new.foo([]).should == ["ModB#foo","A#baz"]
    Super::MS2::B.new.baz([]).should == ["A#baz"]
    Super::MS2::C.new.baz([]).should == ["C#baz","A#baz"]
    Super::MS2::C.new.foo([]).should == ["ModB#foo","C#baz","A#baz"]
  end

  it "can resolve to different methods in an included module method" do
    Super::MultiSuperTargets::A.new.foo.should == :BaseA
    Super::MultiSuperTargets::B.new.foo.should == :BaseB
  end

  it "searches class methods including modules" do
    Super::MS3::A.new.foo([]).should == ["A#foo"]
    Super::MS3::A.foo([]).should == ["ModA#foo"]
    Super::MS3::A.bar([]).should == ["ModA#bar","ModA#foo"]
    Super::MS3::B.new.foo([]).should == ["A#foo"]
    Super::MS3::B.foo([]).should == ["B.foo","ModA#foo"]
    Super::MS3::B.bar([]).should == ["B.bar","ModA#bar","B.foo","ModA#foo"]
  end

  it "searches BasicObject from a module for methods defined there" do
    Super::IncludesFromBasic.new.__send__(:foobar).should == 43
  end

  it "searches BasicObject through another module for methods defined there" do
    Super::IncludesIntermediate.new.__send__(:foobar).should == 42
  end

  it "calls the correct method when the method visibility is modified" do
    Super::MS4::A.new.example.should == 5
  end

  it "calls the correct method when the superclass argument list is different from the subclass" do
    Super::S4::A.new.foo([]).should == ["A#foo"]
    Super::S4::B.new.foo([],"test").should == ["B#foo(a,test)", "A#foo"]
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

    lambda {sub_normal.new.foo}.should raise_error(NoMethodError, /super/)
    lambda {sub_zsuper.new.foo}.should raise_error(NoMethodError, /super/)
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

  it "calls the superclass method when in a block" do
    Super::S6.new.here.should == :good
  end

  it "calls the superclass method when initial method is defined_method'd" do
    Super::S7.new.here.should == :good
  end

  it "can call through a define_method multiple times (caching check)" do
    obj = Super::S7.new

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

    lambda { klass.new.a(:a_called) }.should raise_error(RuntimeError)
  end

  # Rubinius ticket github#157
  it "calls method_missing when a superclass method is not found" do
    Super::MM_B.new.is_a?(Hash).should == false
  end

  # Rubinius ticket github#180
  it "respects the original module a method is aliased from" do
    Super::Alias3.new.name3.should == [:alias2, :alias1]
  end

  it "sees the included version of a module a method is alias from" do
    Super::AliasWithSuper::Trigger.foo.should == [:b, :a]
  end

  it "find super from a singleton class" do
    obj = Super::SingletonCase::Foo.new
    def obj.foobar(array)
      array << :singleton
      super
    end
    obj.foobar([]).should == [:singleton, :foo, :base]
  end

  it "finds super on other objects if a singleton class aliased the method" do
    orig_obj = Super::SingletonAliasCase::Foo.new
    orig_obj.alias_on_singleton
    orig_obj.new_foobar([]).should == [:foo, :base]
    Super::SingletonAliasCase::Foo.new.foobar([]).should == [:foo, :base]
  end

  it "passes along modified rest args when they weren't originally empty" do
    Super::RestArgsWithSuper::B.new.a("bar").should == ["bar", "foo"]
  end

  it "passes along modified rest args when they were originally empty" do
    Super::RestArgsWithSuper::B.new.a.should == ["foo"]
  end

  # https://bugs.ruby-lang.org/issues/14279
  it "passes along reassigned rest args" do
    Super::ZSuperWithRestReassigned::B.new.a("bar").should == ["foo"]
  end

  # Don't run this spec on Appveyor because it uses old Ruby versions
  # The specs ends with segfault on old versions so let's just disable it
  platform_is_not :windows do
    # https://bugs.ruby-lang.org/issues/14279
    it "wraps into array and passes along reassigned rest args with non-array scalar value" do
      Super::ZSuperWithRestReassignedWithScalar::B.new.a("bar").should == ["foo"]
    end
  end

  it "invokes methods from a chain of anonymous modules" do
    Super::AnonymousModuleIncludedTwice.new.a([]).should == ["anon", "anon", "non-anon"]
  end

  it "without explicit arguments can accept a block but still pass the original arguments" do
    Super::ZSuperWithBlock::B.new.a.should == 14
  end

  it "passes along block via reference to method expecting a reference" do
    Super::ZSuperWithBlock::B.new.b.should == [14, 15]
  end

  it "passes along a block via reference to a method that yields" do
    Super::ZSuperWithBlock::B.new.c.should == 16
  end

  it "without explicit arguments passes optional arguments that have a default value" do
    Super::ZSuperWithOptional::B.new.m(1, 2).should == 14
  end

  it "without explicit arguments passes optional arguments that have a non-default value" do
    Super::ZSuperWithOptional::B.new.m(1, 2, 3).should == 3
  end

  it "without explicit arguments passes optional arguments that have a default value but were modified" do
    Super::ZSuperWithOptional::C.new.m(1, 2).should == 100
  end

  it "without explicit arguments passes optional arguments that have a non-default value but were modified" do
    Super::ZSuperWithOptional::C.new.m(1, 2, 3).should == 100
  end

  it "without explicit arguments passes rest arguments" do
    Super::ZSuperWithRest::B.new.m(1, 2, 3).should == [1, 2, 3]
  end

  it "without explicit arguments passes rest arguments including any modifications" do
    Super::ZSuperWithRest::B.new.m_modified(1, 2, 3).should == [1, 14, 3]
  end

  it "without explicit arguments passes arguments and rest arguments" do
    Super::ZSuperWithRestAndOthers::B.new.m(1, 2, 3, 4, 5).should == [3, 4, 5]
  end

  it "without explicit arguments passes arguments and rest arguments including any modifications" do
    Super::ZSuperWithRestAndOthers::B.new.m_modified(1, 2, 3, 4, 5).should == [3, 14, 5]
  end

  it "without explicit arguments that are '_'" do
    Super::ZSuperWithUnderscores::B.new.m(1, 2).should == [1, 2]
  end

  it "without explicit arguments that are '_' including any modifications" do
    Super::ZSuperWithUnderscores::B.new.m_modified(1, 2).should == [14, 2]
  end

  describe 'when using keyword arguments' do
    before :each do
      @req  = Super::Keywords::RequiredArguments.new
      @opts = Super::Keywords::OptionalArguments.new
      @etc  = Super::Keywords::PlaceholderArguments.new

      @req_and_opts = Super::Keywords::RequiredAndOptionalArguments.new
      @req_and_etc  = Super::Keywords::RequiredAndPlaceholderArguments.new
      @opts_and_etc = Super::Keywords::OptionalAndPlaceholderArguments.new

      @req_and_opts_and_etc = Super::Keywords::RequiredAndOptionalAndPlaceholderArguments.new
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
      @req  = Super::RegularAndKeywords::RequiredArguments.new
      @opts = Super::RegularAndKeywords::OptionalArguments.new
      @etc  = Super::RegularAndKeywords::PlaceholderArguments.new

      @req_and_opts = Super::RegularAndKeywords::RequiredAndOptionalArguments.new
      @req_and_etc  = Super::RegularAndKeywords::RequiredAndPlaceholderArguments.new
      @opts_and_etc = Super::RegularAndKeywords::OptionalAndPlaceholderArguments.new

      @req_and_opts_and_etc = Super::RegularAndKeywords::RequiredAndOptionalAndPlaceholderArguments.new
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
      @all = Super::SplatAndKeywords::AllArguments.new
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
