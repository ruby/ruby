require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTP#get2" do
  it "is an alias of Net::HTTP#request_get" do
    Net::HTTP.instance_method(:get2).should == Net::HTTP.instance_method(:request_get)
  end
end
