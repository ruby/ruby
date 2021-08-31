require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Struct.new" do
  it "creates a constant in Struct namespace with string as first argument" do
    struct = Struct.new('Animal', :name, :legs, :eyeballs)
    struct.should == Struct::Animal
    struct.name.should == "Struct::Animal"
  end

  it "overwrites previously defined constants with string as first argument" do
    first = Struct.new('Person', :height, :weight)
    first.should == Struct::Person

    second = nil
    -> {
      second = Struct.new('Person', :hair, :sex)
    }.should complain(/constant/)
    second.should == Struct::Person

    first.members.should_not == second.members
  end

  it "calls to_str on its first argument (constant name)" do
    obj = mock('Foo')
    def obj.to_str() "Foo" end
    struct = Struct.new(obj)
    struct.should == Struct::Foo
    struct.name.should == "Struct::Foo"
  end

  it "creates a new anonymous class with nil first argument" do
    struct = Struct.new(nil, :foo)
    struct.new("bar").foo.should == "bar"
    struct.should be_kind_of(Class)
    struct.name.should be_nil
  end

  it "creates a new anonymous class with symbol arguments" do
    struct = Struct.new(:make, :model)
    struct.should be_kind_of(Class)
    struct.name.should == nil
  end

  it "does not create a constant with symbol as first argument" do
    Struct.new(:Animal2, :name, :legs, :eyeballs)
    Struct.const_defined?("Animal2").should be_false
  end


  it "fails with invalid constant name as first argument" do
    -> { Struct.new('animal', :name, :legs, :eyeballs) }.should raise_error(NameError)
  end

  it "raises a TypeError if object doesn't respond to to_sym" do
    -> { Struct.new(:animal, mock('giraffe'))      }.should raise_error(TypeError)
    -> { Struct.new(:animal, 1.0)                  }.should raise_error(TypeError)
    -> { Struct.new(:animal, Time.now)             }.should raise_error(TypeError)
    -> { Struct.new(:animal, Class)                }.should raise_error(TypeError)
    -> { Struct.new(:animal, nil)                  }.should raise_error(TypeError)
    -> { Struct.new(:animal, true)                 }.should raise_error(TypeError)
    -> { Struct.new(:animal, ['chris', 'evan'])    }.should raise_error(TypeError)
  end

  it "raises a ArgumentError if passed a Hash with an unknown key" do
    -> { Struct.new(:animal, { name: 'chris' }) }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError when there is a duplicate member" do
    -> { Struct.new(:foo, :foo) }.should raise_error(ArgumentError, "duplicate member: foo")
  end

  it "raises a TypeError if object is not a Symbol" do
    obj = mock(':ruby')
    def obj.to_sym() :ruby end
    -> { Struct.new(:animal, obj) }.should raise_error(TypeError)
  end

  it "processes passed block with instance_eval" do
    klass = Struct.new(:something) { @something_else = 'something else entirely!' }
    klass.instance_variables.should include(:@something_else)
  end

  context "with a block" do
    it "allows class to be modified via the block" do
      klass = Struct.new(:version) do
        def platform
          :ruby
        end
      end
      instance = klass.new('2.2')

      instance.version.should == '2.2'
      instance.platform.should == :ruby
    end

    it "passes same struct class to the block" do
      given = nil
      klass = Struct.new(:attr) do |block_parameter|
        given = block_parameter
      end
      klass.should equal(given)
    end
  end

  context "on subclasses" do
    it "creates a constant in subclass' namespace" do
      struct = StructClasses::Apple.new('Computer', :size)
      struct.should == StructClasses::Apple::Computer
    end

    it "creates an instance" do
      StructClasses::Ruby.new.kind_of?(StructClasses::Ruby).should == true
    end

    it "creates reader methods" do
      StructClasses::Ruby.new.should have_method(:version)
      StructClasses::Ruby.new.should have_method(:platform)
    end

    it "creates writer methods" do
      StructClasses::Ruby.new.should have_method(:version=)
      StructClasses::Ruby.new.should have_method(:platform=)
    end

    it "fails with too many arguments" do
      -> { StructClasses::Ruby.new('2.0', 'i686', true) }.should raise_error(ArgumentError)
    end

    ruby_version_is ''...'3.1' do
      it "passes a hash as a normal argument" do
        type = Struct.new(:args)

        obj = suppress_warning {type.new(keyword: :arg)}
        obj2 = type.new(*[{keyword: :arg}])

        obj.should == obj2
        obj.args.should == {keyword: :arg}
        obj2.args.should == {keyword: :arg}
      end
    end

    ruby_version_is '3.2' do
      it "accepts keyword arguments to initialize" do
        type = Struct.new(:args)

        obj = type.new(args: 42)
        obj2 = type.new(42)

        obj.should == obj2
        obj.args.should == 42
        obj2.args.should == 42
      end
    end
  end

  context "keyword_init: true option" do
    before :all do
      @struct_with_kwa = Struct.new(:name, :legs, keyword_init: true)
    end

    it "creates a class that accepts keyword arguments to initialize" do
      obj = @struct_with_kwa.new(name: "elefant", legs: 4)
      obj.name.should == "elefant"
      obj.legs.should == 4
    end

    it "raises when there is a duplicate member" do
      -> { Struct.new(:foo, :foo, keyword_init: true) }.should raise_error(ArgumentError, "duplicate member: foo")
    end

    describe "new class instantiation" do
      it "accepts arguments as hash as well" do
        obj = @struct_with_kwa.new({name: "elefant", legs: 4})
        obj.name.should == "elefant"
        obj.legs.should == 4
      end

      it "allows missing arguments" do
        obj = @struct_with_kwa.new(name: "elefant")
        obj.name.should == "elefant"
        obj.legs.should be_nil
      end

      it "allows no arguments" do
        obj = @struct_with_kwa.new
        obj.name.should be_nil
        obj.legs.should be_nil
      end

      it "raises ArgumentError when passed not declared keyword argument" do
        -> {
          @struct_with_kwa.new(name: "elefant", legs: 4, foo: "bar")
        }.should raise_error(ArgumentError, /unknown keywords: foo/)
      end

      it "raises ArgumentError when passed a list of arguments" do
        -> {
          @struct_with_kwa.new("elefant", 4)
        }.should raise_error(ArgumentError, /wrong number of arguments/)
      end

      it "raises ArgumentError when passed a single non-hash argument" do
        -> {
          @struct_with_kwa.new("elefant")
        }.should raise_error(ArgumentError, /wrong number of arguments/)
      end
    end
  end

  context "keyword_init: false option" do
    before :all do
      @struct_without_kwa = Struct.new(:name, :legs, keyword_init: false)
    end

    it "behaves like it does without :keyword_init option" do
      obj = @struct_without_kwa.new("elefant", 4)
      obj.name.should == "elefant"
      obj.legs.should == 4
    end
  end
end
