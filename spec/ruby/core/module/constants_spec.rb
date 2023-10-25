require_relative '../../spec_helper'
require_relative '../../fixtures/constants'
require_relative 'fixtures/classes'

describe "Module.constants" do
  it "returns an array of the names of all toplevel constants" do
    count = Module.constants.size
    module ConstantSpecsAdded
    end
    Module.constants.size.should == count + 1
    Object.send(:remove_const, :ConstantSpecsAdded)
  end

  it "returns an array of Symbol names" do
    # This in NOT an exhaustive list
    Module.constants.should include(:Array, :Class, :Comparable, :Dir,
                                    :Enumerable, :ENV, :Exception, :FalseClass,
                                    :File, :Float, :Hash, :Integer, :IO,
                                    :Kernel, :Math, :Method, :Module, :NilClass,
                                    :Numeric, :Object, :Range, :Regexp, :String,
                                    :Symbol, :Thread, :Time, :TrueClass)
  end

  it "returns Module's constants when given a parameter" do
    direct = Module.constants(false)
    indirect = Module.constants(true)
    module ConstantSpecsIncludedModule
      MODULE_CONSTANTS_SPECS_INDIRECT = :foo
    end

    class Module
      MODULE_CONSTANTS_SPECS_DIRECT = :bar
      include ConstantSpecsIncludedModule
    end
    (Module.constants(false) - direct).should == [:MODULE_CONSTANTS_SPECS_DIRECT]
    (Module.constants(true) - indirect).sort.should == [:MODULE_CONSTANTS_SPECS_DIRECT, :MODULE_CONSTANTS_SPECS_INDIRECT]

    Module.send(:remove_const, :MODULE_CONSTANTS_SPECS_DIRECT)
    ConstantSpecsIncludedModule.send(:remove_const, :MODULE_CONSTANTS_SPECS_INDIRECT)
  end
end

describe "Module#constants" do
  it "returns an array of Symbol names of all constants defined in the module and all included modules" do
    ConstantSpecs::ContainerA.constants.sort.should == [
      :CS_CONST10, :CS_CONST10_LINE, :CS_CONST23, :CS_CONST24, :CS_CONST5, :ChildA
    ]
  end

  it "returns all constants including inherited when passed true" do
    ConstantSpecs::ContainerA.constants(true).sort.should == [
      :CS_CONST10, :CS_CONST10_LINE, :CS_CONST23, :CS_CONST24, :CS_CONST5, :ChildA
    ]
  end

  it "returns all constants including inherited when passed some object" do
    ConstantSpecs::ContainerA.constants(Object.new).sort.should == [
      :CS_CONST10, :CS_CONST10_LINE, :CS_CONST23, :CS_CONST24, :CS_CONST5, :ChildA
    ]
  end

  it "doesn't returns inherited constants when passed false" do
    ConstantSpecs::ContainerA.constants(false).sort.should == [
      :CS_CONST10, :CS_CONST10_LINE, :CS_CONST23, :CS_CONST5, :ChildA
    ]
  end

  it "doesn't returns inherited constants when passed nil" do
    ConstantSpecs::ContainerA.constants(nil).sort.should == [
      :CS_CONST10, :CS_CONST10_LINE, :CS_CONST23, :CS_CONST5, :ChildA
    ]
  end

  it "returns only public constants" do
    ModuleSpecs::PrivConstModule.constants.should == [:PUBLIC_CONSTANT]
  end

  it "returns only constants starting with an uppercase letter" do
    # e.g. fatal, IO::generic_readable and IO::generic_writable should not be returned by Module#constants
    Object.constants.each { |c| c[0].should == c[0].upcase }
    IO.constants.each { |c| c[0].should == c[0].upcase }
  end
end

describe "Module#constants" do
  before :each do
    ConstantSpecs::ModuleM::CS_CONST251 = :const251
  end

  after :each do
    ConstantSpecs::ModuleM.send(:remove_const, :CS_CONST251)
  end

  it "includes names of constants defined after a module is included" do
    ConstantSpecs::ContainerA.constants.should include(:CS_CONST251)
  end
end
