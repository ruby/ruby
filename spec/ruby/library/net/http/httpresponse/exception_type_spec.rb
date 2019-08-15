require_relative '../../../../spec_helper'
require 'net/http'

describe "Net::HTTPResponse.exception_type" do
  it "returns self's 'EXCEPTION_TYPE' constant" do
    Net::HTTPUnknownResponse.exception_type.should == Net::HTTPError
    Net::HTTPInformation.exception_type.should == Net::HTTPError
    Net::HTTPSuccess.exception_type.should == Net::HTTPError
    Net::HTTPRedirection.exception_type.should == Net::HTTPRetriableError
    ruby_version_is ""..."2.6" do
      Net::HTTPClientError.exception_type.should == Net::HTTPServerException
    end
    ruby_version_is "2.6" do
      Net::HTTPClientError.exception_type.should == Net::HTTPClientException
    end
    Net::HTTPServerError.exception_type.should == Net::HTTPFatalError
  end
end
