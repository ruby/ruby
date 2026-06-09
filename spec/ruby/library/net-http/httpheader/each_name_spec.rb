require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'

describe "Net::HTTPHeader#each_name" do
  it "is an alias of Net::HTTPHeader#each_key" do
    Net::HTTPHeader.instance_method(:each_name).should ==
      Net::HTTPHeader.instance_method(:each_key)
  end
end
