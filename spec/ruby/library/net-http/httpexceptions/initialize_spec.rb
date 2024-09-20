require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'

describe "Net::HTTPExceptions#initialize when passed message, response" do
  before :each do
    @exception = NetHTTPExceptionsSpecs::Simple.new("error message", "a http response")
  end

  it "calls super with the passed message" do
    @exception.message.should == "error message"
  end

  it "sets self's response to the passed response" do
    @exception.response.should == "a http response"
  end
end
