require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "UnboundMethod#bind" do
  before :each do
    @normal_um = UnboundMethodSpecs::Methods.new.method(:foo).unbind
    @parent_um = UnboundMethodSpecs::Parent.new.method(:foo).unbind
    @child1_um = UnboundMethodSpecs::Child1.new.method(:foo).unbind
    @child2_um = UnboundMethodSpecs::Child2.new.method(:foo).unbind
    @normal_um_super = UnboundMethodSpecs::Mod.instance_method(:foo_super)
    @parent_um_super = UnboundMethodSpecs::Parent.new.method(:foo_super).unbind
  end

  it "raises TypeError if object is not kind_of? the Module the method defined in" do
    -> { @normal_um.bind(UnboundMethodSpecs::B.new) }.should raise_error(TypeError)
  end

  it "returns Method for any object that is kind_of? the Module method was extracted from" do
    @normal_um.bind(UnboundMethodSpecs::Methods.new).should be_kind_of(Method)
  end

  it "returns Method on any object when UnboundMethod is unbound from a module" do
    UnboundMethodSpecs::Mod.instance_method(:from_mod).bind(Object.new).should be_kind_of(Method)
  end

  it "the returned Method is equal to the one directly returned by obj.method" do
    obj = UnboundMethodSpecs::Methods.new
    @normal_um.bind(obj).should == obj.method(:foo)
  end

  it "returns Method for any object kind_of? the Module the method is defined in" do
    @parent_um.bind(UnboundMethodSpecs::Child1.new).should be_kind_of(Method)
    @child1_um.bind(UnboundMethodSpecs::Parent.new).should be_kind_of(Method)
    @child2_um.bind(UnboundMethodSpecs::Child1.new).should be_kind_of(Method)
  end

  it "allows binding a Kernel method retrieved from Object on BasicObject" do
    Object.instance_method(:instance_of?).bind(BasicObject.new).call(BasicObject).should == true
  end

  it "returns a callable method" do
    obj = UnboundMethodSpecs::Methods.new
    @normal_um.bind(obj).call.should == obj.foo
  end

  it "binds a Parent's class method to any Child's class methods" do
    m = UnboundMethodSpecs::Parent.method(:class_method).unbind.bind(UnboundMethodSpecs::Child1)
    m.should be_an_instance_of(Method)
    m.call.should == "I am UnboundMethodSpecs::Child1"
  end

  it "will raise when binding a an object singleton's method to another object" do
    other = UnboundMethodSpecs::Parent.new
    p = UnboundMethodSpecs::Parent.new
    class << p
      def singleton_method
        :single
      end
    end
    um = p.method(:singleton_method).unbind
    ->{ um.bind(other) }.should raise_error(TypeError)
  end

  it "allows calling super for module methods bound to hierarchies that do not already have that module" do
    p = UnboundMethodSpecs::Parent.new

    @normal_um_super.bind(p).call.should == true
  end
end
