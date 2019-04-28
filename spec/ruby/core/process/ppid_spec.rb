require_relative '../../spec_helper'

describe "Process.ppid" do
  it "returns the process id of the parent of this process" do
    ruby_exe("puts Process.ppid").should == "#{Process.pid}\n"
  end
end
