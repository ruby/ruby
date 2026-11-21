require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTPResponse#entity" do
  it "is an alias of Net::HTTPResponse#body" do
    Net::HTTPResponse.instance_method(:entity).should ==
      Net::HTTPResponse.instance_method(:body)
  end
end
