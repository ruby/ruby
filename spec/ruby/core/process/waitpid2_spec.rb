require_relative '../../spec_helper'

describe "Process.waitpid2" do
  it "is an alias of Process.wait2" do
    Process.method(:waitpid2).should == Process.method(:wait2)
  end
end
