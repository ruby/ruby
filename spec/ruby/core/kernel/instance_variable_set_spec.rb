require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#instance_variable_set" do
  it "sets the value of the specified instance variable" do
    dog = Class.new do
      def initialize(p1, p2)
        @a, @b = p1, p2
      end
    end
    dog.new('cat', 99).instance_variable_set(:@a, 'dog').should == "dog"
  end

  it "sets the value of the instance variable when no instance variables exist yet" do
    no_variables = Class.new
    no_variables.new.instance_variable_set(:@a, "new").should == "new"
  end

  it "raises a NameError exception if the argument is not of form '@x'" do
    no_dog = Class.new
    -> { no_dog.new.instance_variable_set(:c, "cat") }.should raise_error(NameError)
  end

  it "raises a NameError exception if the argument is an invalid instance variable name" do
    digit_dog = Class.new
    -> { digit_dog.new.instance_variable_set(:"@0", "cat") }.should raise_error(NameError)
  end

  it "raises a NameError when the argument is '@'" do
    dog_at = Class.new
    -> { dog_at.new.instance_variable_set(:"@", "cat") }.should raise_error(NameError)
  end

  it "raises a TypeError if the instance variable name is an Integer" do
    -> { "".instance_variable_set(1, 2) }.should raise_error(TypeError)
  end

  it "raises a TypeError if the instance variable name is an object that does not respond to to_str" do
    class KernelSpecs::A; end
    -> { "".instance_variable_set(KernelSpecs::A.new, 3) }.should raise_error(TypeError)
  end

  it "raises a NameError if the passed object, when coerced with to_str, does not start with @" do
    class KernelSpecs::B
      def to_str
        ":c"
      end
    end
    -> { "".instance_variable_set(KernelSpecs::B.new, 4) }.should raise_error(NameError)
  end

  it "raises a NameError if pass an object that cannot be a symbol" do
    -> { "".instance_variable_set(:c, 1) }.should raise_error(NameError)
  end

  it "accepts as instance variable name any instance of a class that responds to to_str" do
    class KernelSpecs::C
      def initialize
        @a = 1
      end
      def to_str
        "@a"
      end
    end
    KernelSpecs::C.new.instance_variable_set(KernelSpecs::C.new, 2).should == 2
  end

  describe "on frozen objects" do
    before :each do
      klass = Class.new do
        attr_reader :ivar
        def initialize
          @ivar = :origin
        end
      end

      @frozen = klass.new.freeze
    end

    it "keeps stored object after any exceptions" do
      -> { @frozen.instance_variable_set(:@ivar, :replacement) }.should raise_error(Exception)
      @frozen.ivar.should equal(:origin)
    end

    it "raises a FrozenError when passed replacement is identical to stored object" do
      -> { @frozen.instance_variable_set(:@ivar, :origin) }.should raise_error(FrozenError)
    end

    it "raises a FrozenError when passed replacement is different from stored object" do
      -> { @frozen.instance_variable_set(:@ivar, :replacement) }.should raise_error(FrozenError)
    end
  end
end
