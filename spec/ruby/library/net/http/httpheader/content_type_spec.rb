require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'
require_relative 'shared/set_content_type'

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
    @headers.content_type.should be_nil
  end
end

describe "Net::HTTPHeader#content_type=" do
  it_behaves_like :net_httpheader_set_content_type, :content_type=
end
