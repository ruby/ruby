require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTPHeader#canonical_each" do
  it "is an alias of Net::HTTPHeader#each_capitalized" do
    Net::HTTPHeader.instance_method(:canonical_each).should ==
      Net::HTTPHeader.instance_method(:each_capitalized)
  end
end
