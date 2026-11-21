require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTPHeader#each" do
  it "is an alias of Net::HTTPHeader#each_header" do
    Net::HTTPHeader.instance_method(:each).should ==
      Net::HTTPHeader.instance_method(:each_header)
  end
end
