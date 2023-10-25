require_relative '../../spec_helper'

describe "SystemExit#success?" do
  it "returns true if the process exited successfully" do
    -> { exit 0 }.should raise_error(SystemExit) { |e|
      e.should.success?
    }
  end

  it "returns false if the process exited unsuccessfully" do
    -> { exit(-1) }.should raise_error(SystemExit) { |e|
      e.should_not.success?
    }
  end
end
