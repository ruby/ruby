require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTP#put2" do
  it "is an alias of Net::HTTP#request_put" do
    Net::HTTP.instance_method(:put2).should == Net::HTTP.instance_method(:request_put)
  end
end
