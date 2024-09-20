require_relative '../../spec_helper'
require_relative 'shared/dup'

describe "Proc#dup" do
  it_behaves_like :proc_dup, :dup

  it "resets frozen status" do
    proc = Proc.new { }
    proc.freeze
    proc.frozen?.should == true
    proc.dup.frozen?.should == false
  end
end
