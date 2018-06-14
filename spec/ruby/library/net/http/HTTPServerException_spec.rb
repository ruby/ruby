require_relative '../../../spec_helper'
require 'net/http'

ruby_version_is ""..."2.6" do
  describe "Net::HTTPServerException" do
    it "is a subclass of Net::ProtoServerError" do
      Net::HTTPServerException.should < Net::ProtoServerError
    end

    it "includes the Net::HTTPExceptions module" do
      Net::HTTPServerException.should < Net::HTTPExceptions
    end
  end
end

ruby_version_is "2.6" do
  describe "Net::HTTPServerException" do
    it "is a subclass of Net::ProtoServerError and is warned as deprecated" do
      lambda { Net::HTTPServerException.should < Net::ProtoServerError }.should complain(/warning: constant Net::HTTPServerException is deprecated/)
    end

    it "includes the Net::HTTPExceptions module and is warned as deprecated" do
      lambda { Net::HTTPServerException.should < Net::HTTPExceptions }.should complain(/warning: constant Net::HTTPServerException is deprecated/)
    end
  end
end
