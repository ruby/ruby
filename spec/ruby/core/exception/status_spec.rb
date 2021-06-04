require_relative '../../spec_helper'

describe "SystemExit#status" do
  it "returns the exit status" do
    -> { exit 42 }.should raise_error(SystemExit) { |e|
      e.status.should == 42
    }
  end
end
