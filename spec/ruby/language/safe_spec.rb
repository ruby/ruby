require_relative '../spec_helper'

describe "The $SAFE variable" do
  it "$SAFE is a regular global variable" do
    $SAFE.should == nil
    $SAFE = 42
    $SAFE.should == 42
  ensure
    $SAFE = nil
  end
end
