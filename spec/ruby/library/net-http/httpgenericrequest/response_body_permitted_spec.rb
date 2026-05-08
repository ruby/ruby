require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTPGenericRequest#response_body_permitted?" do
  it "returns true when the response is expected to have a body" do
    request = Net::HTTPGenericRequest.new("POST", true, true, "/some/path")
    request.response_body_permitted?.should == true

    request = Net::HTTPGenericRequest.new("POST", true, false, "/some/path")
    request.response_body_permitted?.should == false
  end
end
