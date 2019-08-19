require_relative '../../../spec_helper'
require 'net/http'

ruby_version_is "2.6" do
  describe "Net::HTTPClientException" do
    it "is a subclass of Net::ProtoServerError" do
      Net::HTTPClientException.should < Net::ProtoServerError
    end

    it "includes the Net::HTTPExceptions module" do
      Net::HTTPClientException.should < Net::HTTPExceptions
    end
  end
end
