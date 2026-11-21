require_relative '../../spec_helper'

describe "Process.waitpid" do
  it "is an alias of Process.wait" do
    Process.method(:waitpid).should == Process.method(:wait)
  end
end
