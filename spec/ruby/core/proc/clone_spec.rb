require_relative '../../spec_helper'
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
end
