require_relative '../spec_helper'

describe "The $SAFE variable" do
  ruby_version_is ""..."3.0" do
    it "warn when access" do
      -> {
        $SAFE
      }.should complain(/\$SAFE will become a normal global variable in Ruby 3.0/)
    end

    it "warn when set" do
      -> {
        $SAFE = 1
      }.should complain(/\$SAFE will become a normal global variable in Ruby 3.0/)
    end
  end

  ruby_version_is "3.0" do
    it "$SAFE is a regular global variable" do
      $SAFE.should == nil
      $SAFE = 42
      $SAFE.should == 42
    ensure
      $SAFE = nil
    end
  end
end
