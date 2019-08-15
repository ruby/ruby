require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTPFatalError" do
  it "is a subclass of Net::ProtoFatalError" do
    Net::HTTPFatalError.should < Net::ProtoFatalError
  end

  it "includes the Net::HTTPExceptions module" do
    Net::HTTPFatalError.should < Net::HTTPExceptions
  end
end
