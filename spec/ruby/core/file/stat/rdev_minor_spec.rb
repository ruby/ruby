require_relative '../../../spec_helper'

describe "File::Stat#rdev_minor" do
  before :each do
    @name = tmp("file.txt")
    touch(@name)
  end

  after :each do
    rm_r @name
  end

  platform_is_not :windows do
    it "returns the minor part of File::Stat#rdev" do
      File.stat(@name).rdev_minor.should.is_a?(Integer)
    end
  end

  platform_is :windows do
    it "returns nil" do
      File.stat(@name).rdev_minor.should == nil
    end
  end
end
