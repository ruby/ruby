require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'shared/dup'

describe "Proc#clone" do
  it_behaves_like :proc_dup, :clone

  ruby_bug "cloning a frozen proc is broken on Ruby 3.3", "3.3"..."3.4" do
    it "preserves frozen status" do
      proc = Proc.new { }
      proc.freeze
      proc.frozen?.should == true
      proc.clone.frozen?.should == true
    end
  end

  ruby_version_is "3.3" do
    it "calls #initialize_clone on subclass" do
      obj = ProcSpecs::MyProc2.new(:a, 2) { }
      dup = obj.clone

      dup.should_not equal(obj)
      dup.class.should == ProcSpecs::MyProc2

      dup.first.should == :a
      dup.second.should == 2
      dup.initializer.should == :clone
    end
  end
end
