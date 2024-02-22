require_relative '../../spec_helper'
require 'net/http'

describe "Net::HTTPServerException" do
  it "is a subclass of Net::ProtoServerError and is warned as deprecated" do
    -> { Net::HTTPServerException.should < Net::ProtoServerError }.should complain(/warning: constant Net::HTTPServerException is deprecated/)
  end

  it "includes the Net::HTTPExceptions module and is warned as deprecated" do
    -> { Net::HTTPServerException.should < Net::HTTPExceptions }.should complain(/warning: constant Net::HTTPServerException is deprecated/)
  end
end
