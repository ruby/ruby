require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTP.version_1_1?" do
  it "returns the state of net/http 1.1 features" do
    Net::HTTP.version_1_2
    Net::HTTP.version_1_1?.should == false
  end
end
