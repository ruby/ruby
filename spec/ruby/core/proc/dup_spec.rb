require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'shared/dup'

describe "Proc#dup" do
  it_behaves_like :proc_dup, :dup

  it "resets frozen status" do
    proc = Proc.new { }
    proc.freeze
    proc.frozen?.should == true
    proc.dup.frozen?.should == false
  end

  ruby_version_is "3.3" do
    it "calls #initialize_dup on subclass" do
      obj = ProcSpecs::MyProc2.new(:a, 2) { }
      dup = obj.dup

      dup.should_not equal(obj)
      dup.class.should == ProcSpecs::MyProc2

      dup.first.should == :a
      dup.second.should == 2
      dup.initializer.should == :dup
    end
  end
end
