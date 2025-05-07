require_relative '../../spec_helper'

describe "Struct::Group" do
  it "is no longer defined" do
    Struct.should_not.const_defined?(:Group)
  end
end

describe "Struct::Passwd" do
  it "is no longer defined" do
    Struct.should_not.const_defined?(:Passwd)
  end
end
