require_relative '../../../spec_helper'

describe "File::Stat#rdev_major" do
  before :each do
    @name = tmp("file.txt")
    touch(@name)
  end

  after :each do
    rm_r @name
  end

  platform_is_not :windows do
    it "returns the major part of File::Stat#rdev" do
      File.stat(@name).rdev_major.should be_kind_of(Integer)
    end
  end

  platform_is :windows do
    it "returns nil" do
      File.stat(@name).rdev_major.should be_nil
    end
  end
end
