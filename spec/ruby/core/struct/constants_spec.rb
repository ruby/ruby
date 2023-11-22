require_relative '../../spec_helper'

ruby_version_is "3.2" do
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
end
