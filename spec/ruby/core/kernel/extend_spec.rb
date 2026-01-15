require_relative '../../spec_helper'
require_relative 'fixtures/classes'

module KernelSpecs::M
  def self.extend_object(o)
    ScratchPad << "extend_object"
    super
  end

  def self.extended(o)
    ScratchPad << "extended"
    super
  end

  def self.append_features(o)
    ScratchPad << "append_features"
    super
  end
end

describe "Kernel#extend" do
  before :each do
    ScratchPad.record []
  end

  it "requires multiple arguments" do
    Object.new.method(:extend).arity.should < 0
  end

  it "calls extend_object on argument" do
    o = mock('o')
    o.extend KernelSpecs::M
    ScratchPad.recorded.include?("extend_object").should == true
  end

  it "does not calls append_features on arguments metaclass" do
    o = mock('o')
    o.extend KernelSpecs::M
    ScratchPad.recorded.include?("append_features").should == false
  end

  it "calls extended on argument" do
    o = mock('o')
    o.extend KernelSpecs::M
    ScratchPad.recorded.include?("extended").should == true
  end

  it "makes the class a kind_of? the argument" do
    c = Class.new do
      extend KernelSpecs::M
    end
    (c.kind_of? KernelSpecs::M).should == true
  end

  it "raises an ArgumentError when no arguments given" do
    -> { Object.new.extend }.should raise_error(ArgumentError)
  end

  it "raises a TypeError when the argument is not a Module" do
    o = mock('o')
    klass = Class.new
    -> { o.extend(klass) }.should raise_error(TypeError)
  end

  describe "on frozen instance" do
    before :each do
      @frozen = Object.new.freeze
      @module = KernelSpecs::M
    end

    it "raises an ArgumentError when no arguments given" do
      -> { @frozen.extend }.should raise_error(ArgumentError)
    end

    it "raises a FrozenError" do
      -> { @frozen.extend @module }.should raise_error(FrozenError)
    end
  end

  it "updated class methods of a module when it extends self and includes another module" do
    a = Module.new do
      extend self
    end
    b = Module.new do
      def foo; :foo; end
    end

    a.include b
    a.foo.should == :foo
  end
end
