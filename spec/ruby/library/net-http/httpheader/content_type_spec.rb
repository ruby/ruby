require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'

describe "Net::HTTPHeader#content_type" do
  before :each do
    @headers = NetHTTPHeaderSpecs::Example.new
  end

  it "returns the content type string, as per 'Content-Type' header entry" do
    @headers["Content-Type"] = "text/html"
    @headers.content_type.should == "text/html"

    @headers["Content-Type"] = "text/html;charset=utf-8"
    @headers.content_type.should == "text/html"
  end

  it "returns nil if the 'Content-Type' header entry does not exist" do
    @headers.content_type.should == nil
  end
end

describe "Net::HTTPHeader#content_type=" do
  it "is an alias of Net::HTTPHeader#set_content_type" do
    Net::HTTPHeader.instance_method(:content_type=).should ==
      Net::HTTPHeader.instance_method(:set_content_type)
  end
end
