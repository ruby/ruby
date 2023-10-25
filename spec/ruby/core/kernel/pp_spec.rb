require_relative '../../spec_helper'

describe "Kernel#pp" do
  it "lazily loads the 'pp' library and delegates the call to that library" do
    # Run in child process to ensure 'pp' hasn't been loaded yet.
    output = ruby_exe("pp [1, 2, 3]")
    output.should == "[1, 2, 3]\n"
  end
end
