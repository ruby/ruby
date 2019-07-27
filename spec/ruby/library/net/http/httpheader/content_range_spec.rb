require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'

describe "Net::HTTPHeader#content_range" do
  before :each do
    @headers = NetHTTPHeaderSpecs::Example.new
  end

  it "returns a Range object that represents the 'Content-Range' header entry" do
    @headers["Content-Range"] = "bytes 0-499/1234"
    @headers.content_range.should == (0..499)

    @headers["Content-Range"] = "bytes 500-1233/1234"
    @headers.content_range.should == (500..1233)
  end

  it "returns nil when there is no 'Content-Range' header entry" do
    @headers.content_range.should be_nil
  end

  it "raises a Net::HTTPHeaderSyntaxError when the 'Content-Range' has an invalid format" do
    @headers["Content-Range"] = "invalid"
    -> { @headers.content_range }.should raise_error(Net::HTTPHeaderSyntaxError)

    @headers["Content-Range"] = "bytes 123-abc"
    -> { @headers.content_range }.should raise_error(Net::HTTPHeaderSyntaxError)

    @headers["Content-Range"] = "bytes abc-123"
    -> { @headers.content_range }.should raise_error(Net::HTTPHeaderSyntaxError)
  end
end
