require_relative '../../../../spec_helper'
require 'net/http'

describe "Net::HTTPResponse.body_permitted?" do
  it "returns true if this response type can have a response body" do
    Net::HTTPUnknownResponse.should.body_permitted?
    Net::HTTPInformation.should_not.body_permitted?
    Net::HTTPSuccess.should.body_permitted?
    Net::HTTPRedirection.should.body_permitted?
    Net::HTTPClientError.should.body_permitted?
    Net::HTTPServerError.should.body_permitted?
  end
end
