require_relative '../../spec_helper'

describe "SystemExit#success?" do
  it "returns true when the status is 0" do
    s = SystemExit.new 0
    s.should.success?
  end

  it "returns false when the status is not 0" do
    s = SystemExit.new 1
    s.should_not.success?
  end
end
