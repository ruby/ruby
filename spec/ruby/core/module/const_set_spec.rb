require_relative '../../spec_helper'
require_relative '../../fixtures/constants'

describe "Module#const_set" do
  it "sets the constant specified by a String or Symbol to the given value" do
    ConstantSpecs.const_set :CS_CONST401, :const401
    ConstantSpecs::CS_CONST401.should == :const401

    ConstantSpecs.const_set "CS_CONST402", :const402
    ConstantSpecs.const_get(:CS_CONST402).should == :const402
  end

  it "returns the value set" do
    ConstantSpecs.const_set(:CS_CONST403, :const403).should == :const403
  end

  it "sets the name of an anonymous module" do
    m = Module.new
    ConstantSpecs.const_set(:CS_CONST1000, m)
    m.name.should == "ConstantSpecs::CS_CONST1000"
  end

  it "does not set the name of a module scoped by an anonymous module" do
    a, b = Module.new, Module.new
    a.const_set :B, b
    b.name.should be_nil
  end

  it "sets the name of contained modules when assigning a toplevel anonymous module" do
    a, b, c, d = Module.new, Module.new, Module.new, Module.new
    a::B = b
    a::B::C = c
    a::B::C::E = c
    a::D = d

    Object.const_set :ModuleSpecs_CS3, a
    a.name.should == "ModuleSpecs_CS3"
    b.name.should == "ModuleSpecs_CS3::B"
    c.name.should == "ModuleSpecs_CS3::B::C"
    d.name.should == "ModuleSpecs_CS3::D"
  end

  it "raises a NameError if the name does not start with a capital letter" do
    lambda { ConstantSpecs.const_set "name", 1 }.should raise_error(NameError)
  end

  it "raises a NameError if the name starts with a non-alphabetic character" do
    lambda { ConstantSpecs.const_set "__CONSTX__", 1 }.should raise_error(NameError)
    lambda { ConstantSpecs.const_set "@Name", 1 }.should raise_error(NameError)
    lambda { ConstantSpecs.const_set "!Name", 1 }.should raise_error(NameError)
    lambda { ConstantSpecs.const_set "::Name", 1 }.should raise_error(NameError)
  end

  it "raises a NameError if the name contains non-alphabetic characters except '_'" do
    ConstantSpecs.const_set("CS_CONST404", :const404).should == :const404
    lambda { ConstantSpecs.const_set "Name=", 1 }.should raise_error(NameError)
    lambda { ConstantSpecs.const_set "Name?", 1 }.should raise_error(NameError)
  end

  it "calls #to_str to convert the given name to a String" do
    name = mock("CS_CONST405")
    name.should_receive(:to_str).and_return("CS_CONST405")
    ConstantSpecs.const_set(name, :const405).should == :const405
    ConstantSpecs::CS_CONST405.should == :const405
  end

  it "raises a TypeError if conversion to a String by calling #to_str fails" do
    name = mock('123')
    lambda { ConstantSpecs.const_set name, 1 }.should raise_error(TypeError)

    name.should_receive(:to_str).and_return(123)
    lambda { ConstantSpecs.const_set name, 1 }.should raise_error(TypeError)
  end

  describe "when overwriting an existing constant" do
    it "warns if the previous value was a normal value" do
      mod = Module.new
      mod.const_set :Foo, 42
      -> {
        mod.const_set :Foo, 1
      }.should complain(/already initialized constant/)
      mod.const_get(:Foo).should == 1
    end

    it "does not warn if the previous value was an autoload" do
      mod = Module.new
      mod.autoload :Foo, "not-existing"
      -> {
        mod.const_set :Foo, 1
      }.should_not complain
      mod.const_get(:Foo).should == 1
    end

    it "does not warn if the previous value was undefined" do
      path = fixture(__FILE__, "autoload_o.rb")
      ScratchPad.record []
      mod = Module.new

      mod.autoload :Foo, path
      -> { mod::Foo }.should raise_error(NameError)

      mod.should have_constant(:Foo)
      mod.const_defined?(:Foo).should == false
      mod.autoload?(:Foo).should == nil

      -> {
        mod.const_set :Foo, 1
      }.should_not complain
      mod.const_get(:Foo).should == 1
    end

    it "does not warn if the new value is an autoload" do
      mod = Module.new
      mod.const_set :Foo, 42
      -> {
        mod.autoload :Foo, "not-existing"
      }.should_not complain
      mod.const_get(:Foo).should == 42
    end
  end

  describe "on a frozen module" do
    before :each do
      @frozen = Module.new.freeze
      @name = :Foo
    end

    it "raises a #{frozen_error_class} before setting the name" do
      lambda { @frozen.const_set @name, nil }.should raise_error(frozen_error_class)
      @frozen.should_not have_constant(@name)
    end
  end
end
