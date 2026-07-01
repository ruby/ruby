require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTP#post2" do
  it "is an alias of Net::HTTP#request_post" do
    Net::HTTP.instance_method(:post2).should == Net::HTTP.instance_method(:request_post)
  end
end
