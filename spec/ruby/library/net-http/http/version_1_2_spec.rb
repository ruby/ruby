require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTP.version_1_2" do
  it "turns on net/http 1.2 features" do
    Net::HTTP.version_1_2

    Net::HTTP.version_1_2?.should == true
    Net::HTTP.version_1_1?.should == false
  end

  it "returns true" do
    Net::HTTP.version_1_2.should == true
  end
end

describe "Net::HTTP.version_1_2?" do
  it "returns the state of net/http 1.2 features" do
    Net::HTTP.version_1_2
    Net::HTTP.version_1_2?.should == true
  end
end
