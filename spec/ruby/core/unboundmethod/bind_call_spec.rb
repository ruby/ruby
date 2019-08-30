require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is '2.7' do
  describe "UnboundMethod#bind_call" do
    before :each do
      @normal_um = UnboundMethodSpecs::Methods.new.method(:foo).unbind
      @parent_um = UnboundMethodSpecs::Parent.new.method(:foo).unbind
      @child1_um = UnboundMethodSpecs::Child1.new.method(:foo).unbind
      @child2_um = UnboundMethodSpecs::Child2.new.method(:foo).unbind
    end

    it "raises TypeError if object is not kind_of? the Module the method defined in" do
      -> { @normal_um.bind_call(UnboundMethodSpecs::B.new) }.should raise_error(TypeError)
    end

    it "binds and calls the method if object is kind_of the Module the method defined in" do
      @normal_um.bind_call(UnboundMethodSpecs::Methods.new).should == true
    end

    it "binds and calls the method on any object when UnboundMethod is unbound from a module" do
      UnboundMethodSpecs::Mod.instance_method(:from_mod).bind_call(Object.new).should == nil
    end

    it "binds and calls the method for any object kind_of? the Module the method is defined in" do
      @parent_um.bind_call(UnboundMethodSpecs::Child1.new).should == nil
      @child1_um.bind_call(UnboundMethodSpecs::Parent.new).should == nil
      @child2_um.bind_call(UnboundMethodSpecs::Child1.new).should == nil
    end

    it "binds and calls a Kernel method retrieved from Object on BasicObject" do
      Object.instance_method(:instance_of?).bind_call(BasicObject.new, BasicObject).should == true
    end

    it "binds and calls a Parent's class method to any Child's class methods" do
      um = UnboundMethodSpecs::Parent.method(:class_method).unbind
      um.bind_call(UnboundMethodSpecs::Child1).should == "I am UnboundMethodSpecs::Child1"
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
      ->{ um.bind_call(other) }.should raise_error(TypeError)
    end
  end
end
