require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTP#head2" do
  it "is an alias of Net::HTTP#request_head" do
    Net::HTTP.instance_method(:head2).should == Net::HTTP.instance_method(:request_head)
  end
end
