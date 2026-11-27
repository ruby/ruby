require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'

describe "Net::HTTPHeader#range" do
  before :each do
    @headers = NetHTTPHeaderSpecs::Example.new
  end

  it "returns a Range object that represents the 'Range' header entry" do
    @headers["Range"] = "bytes=0-499"
    @headers.range.should == [0..499]

    @headers["Range"] = "bytes=500-1233"
    @headers.range.should == [500..1233]

    @headers["Range"] = "bytes=10-"
    @headers.range.should == [10..-1]

    @headers["Range"] = "bytes=-10"
    @headers.range.should == [-10..-1]
  end

  it "returns nil when there is no 'Range' header entry" do
    @headers.range.should == nil
  end

  it "raises a Net::HTTPHeaderSyntaxError when the 'Range' has an invalid format" do
    @headers["Range"] = "invalid"
    -> { @headers.range }.should.raise(Net::HTTPHeaderSyntaxError)

    @headers["Range"] = "bytes 123-abc"
    -> { @headers.range }.should.raise(Net::HTTPHeaderSyntaxError)

    @headers["Range"] = "bytes abc-123"
    -> { @headers.range }.should.raise(Net::HTTPHeaderSyntaxError)
  end

  it "raises a Net::HTTPHeaderSyntaxError when the 'Range' was not specified" do
    @headers["Range"] = "bytes=-"
    -> { @headers.range }.should.raise(Net::HTTPHeaderSyntaxError)
  end
end

describe "Net::HTTPHeader#range=" do
  it "is an alias of Net::HTTPHeader#set_range" do
    Net::HTTPHeader.instance_method(:range=).should ==
      Net::HTTPHeader.instance_method(:set_range)
  end
end
