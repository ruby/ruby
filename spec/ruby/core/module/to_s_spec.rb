require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module#to_s" do
  it 'returns the name of the module if it has a name' do
    Enumerable.to_s.should == 'Enumerable'
    String.to_s.should == 'String'
  end

  it "returns the full constant path leading to the module" do
    ModuleSpecs::LookupMod.to_s.should == "ModuleSpecs::LookupMod"
  end

  it "works with an anonymous module" do
    m = Module.new
    m.to_s.should =~ /\A#<Module:0x\h+>\z/
  end

  it "works with an anonymous class" do
    c = Class.new
    c.to_s.should =~ /\A#<Class:0x\h+>\z/
  end

  it 'for the singleton class of an object of an anonymous class' do
    klass = Class.new
    obj = klass.new
    sclass = obj.singleton_class
    sclass.to_s.should == "#<Class:#{obj}>"
    sclass.to_s.should =~ /\A#<Class:#<#{klass}:0x\h+>>\z/
    sclass.to_s.should =~ /\A#<Class:#<#<Class:0x\h+>:0x\h+>>\z/
  end

  it 'for a singleton class of a module includes the module name' do
    ModuleSpecs.singleton_class.to_s.should == '#<Class:ModuleSpecs>'
  end

  it 'for a metaclass includes the class name' do
    ModuleSpecs::NamedClass.singleton_class.to_s.should == '#<Class:ModuleSpecs::NamedClass>'
  end

  it 'for objects includes class name and object ID' do
    obj = ModuleSpecs::NamedClass.new
    obj.singleton_class.to_s.should =~ /\A#<Class:#<ModuleSpecs::NamedClass:0x\h+>>\z/
  end
end
