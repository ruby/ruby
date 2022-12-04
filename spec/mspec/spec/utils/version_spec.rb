require 'spec_helper'
require 'mspec/utils/version'

RSpec.describe SpecVersion, "#to_s" do
  it "returns the string with which it was initialized" do
    expect(SpecVersion.new("1.8").to_s).to eq("1.8")
    expect(SpecVersion.new("2.118.9").to_s).to eq("2.118.9")
  end
end

RSpec.describe SpecVersion, "#to_str" do
  it "returns the same string as #to_s" do
    version = SpecVersion.new("2.118.9")
    expect(version.to_str).to eq(version.to_s)
  end
end

RSpec.describe SpecVersion, "#to_i with ceil = false" do
  it "returns an integer representation of the version string" do
    expect(SpecVersion.new("2.23.10").to_i).to eq(1022310)
  end

  it "replaces missing version parts with zeros" do
    expect(SpecVersion.new("1.8").to_i).to eq(1010800)
    expect(SpecVersion.new("1.8.6").to_i).to eq(1010806)
  end
end

RSpec.describe SpecVersion, "#to_i with ceil = true" do
  it "returns an integer representation of the version string" do
    expect(SpecVersion.new("1.8.6", true).to_i).to eq(1010806)
  end

  it "fills in 9s for missing tiny values" do
    expect(SpecVersion.new("1.8", true).to_i).to eq(1010899)
    expect(SpecVersion.new("1.8.6", true).to_i).to eq(1010806)
  end
end

RSpec.describe SpecVersion, "#to_int" do
  it "returns the same value as #to_i" do
    version = SpecVersion.new("4.16.87")
    expect(version.to_int).to eq(version.to_i)
  end
end
