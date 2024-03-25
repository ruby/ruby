require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTP.proxy_class?" do
  it "returns true if self is a class created with Net::HTTP.Proxy" do
    Net::HTTP.proxy_class?.should be_false
    Net::HTTP.Proxy("localhost").proxy_class?.should be_true
  end
end
