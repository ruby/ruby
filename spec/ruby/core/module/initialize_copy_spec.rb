require_relative '../../spec_helper'

describe "Module#initialize_copy" do
  it "should retain singleton methods when duped" do
    mod = Module.new
    def mod.hello
    end
    mod.dup.methods(false).should == [:hello]
  end
end
