require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTPHeader#length" do
  it "is an alias of Net::HTTPHeader#size" do
    Net::HTTPHeader.instance_method(:length).should ==
      Net::HTTPHeader.instance_method(:size)
  end
end
