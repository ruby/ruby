require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module#initialize" do
  it "accepts a block" do
    m = Module.new do
      const_set :A, "A"
    end
    m.const_get("A").should == "A"
  end

  it "is called on subclasses" do
    m = ModuleSpecs::SubModule.new
    m.special.should == 10
    m.methods.should_not == nil
    m.constants.should_not == nil
  end
end
