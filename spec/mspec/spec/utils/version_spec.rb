require 'spec_helper'
require 'mspec/utils/version'

describe SpecVersion, "#to_s" do
  it "returns the string with which it was initialized" do
    SpecVersion.new("1.8").to_s.should == "1.8"
    SpecVersion.new("2.118.9").to_s.should == "2.118.9"
  end
end

describe SpecVersion, "#to_str" do
  it "returns the same string as #to_s" do
    version = SpecVersion.new("2.118.9")
    version.to_str.should == version.to_s
  end
end

describe SpecVersion, "#to_i with ceil = false" do
  it "returns an integer representation of the version string" do
    SpecVersion.new("2.23.10").to_i.should == 1022310
  end

  it "replaces missing version parts with zeros" do
    SpecVersion.new("1.8").to_i.should == 1010800
    SpecVersion.new("1.8.6").to_i.should == 1010806
  end
end

describe SpecVersion, "#to_i with ceil = true" do
  it "returns an integer representation of the version string" do
    SpecVersion.new("1.8.6", true).to_i.should == 1010806
  end

  it "fills in 9s for missing tiny values" do
    SpecVersion.new("1.8", true).to_i.should == 1010899
    SpecVersion.new("1.8.6", true).to_i.should == 1010806
  end
end

describe SpecVersion, "#to_int" do
  it "returns the same value as #to_i" do
    version = SpecVersion.new("4.16.87")
    version.to_int.should == version.to_i
  end
end
