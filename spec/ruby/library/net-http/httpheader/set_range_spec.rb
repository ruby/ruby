require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'

describe "Net::HTTPHeader#set_range" do
  before :each do
    @headers = NetHTTPHeaderSpecs::Example.new
  end

  describe "when passed nil" do
    it "returns nil" do
      @headers.set_range(nil).should == nil
    end

    it "deletes the 'Range' header entry" do
      @headers["Range"] = "bytes 0-499/1234"
      @headers.set_range(nil)
      @headers["Range"].should == nil
    end
  end

  describe "when passed Numeric" do
    it "sets the 'Range' header entry based on the passed Numeric" do
      @headers.set_range(10)
      @headers["Range"].should == "bytes=0-9"

      @headers.set_range(-10)
      @headers["Range"].should == "bytes=-10"

      @headers.set_range(10.9)
      @headers["Range"].should == "bytes=0-9"
    end
  end

  describe "when passed Range" do
    it "sets the 'Range' header entry based on the passed Range" do
      @headers.set_range(10..200)
      @headers["Range"].should == "bytes=10-200"

      @headers.set_range(1..5)
      @headers["Range"].should == "bytes=1-5"

      @headers.set_range(1...5)
      @headers["Range"].should == "bytes=1-4"

      @headers.set_range(234..567)
      @headers["Range"].should == "bytes=234-567"

      @headers.set_range(-5..-1)
      @headers["Range"].should == "bytes=-5"

      @headers.set_range(1..-1)
      @headers["Range"].should == "bytes=1-"
    end

    it "raises a Net::HTTPHeaderSyntaxError when the first Range element is negative" do
      -> { @headers.set_range(-10..5) }.should.raise(Net::HTTPHeaderSyntaxError)
    end

    it "raises a Net::HTTPHeaderSyntaxError when the last Range element is negative" do
      -> { @headers.set_range(10..-5) }.should.raise(Net::HTTPHeaderSyntaxError)
    end

    it "raises a Net::HTTPHeaderSyntaxError when the last Range element is smaller than the first" do
      -> { @headers.set_range(10..5) }.should.raise(Net::HTTPHeaderSyntaxError)
    end
  end

  describe "when passed start, end" do
    it "sets the 'Range' header entry based on the passed start and length values" do
      @headers.set_range(10, 200)
      @headers["Range"].should == "bytes=10-209"

      @headers.set_range(1, 5)
      @headers["Range"].should == "bytes=1-5"

      @headers.set_range(234, 567)
      @headers["Range"].should == "bytes=234-800"
    end

    it "raises a Net::HTTPHeaderSyntaxError when start is negative" do
      -> { @headers.set_range(-10, 5) }.should.raise(Net::HTTPHeaderSyntaxError)
    end

    it "raises a Net::HTTPHeaderSyntaxError when start + length is negative" do
      -> { @headers.set_range(10, -15) }.should.raise(Net::HTTPHeaderSyntaxError)
    end

    it "raises a Net::HTTPHeaderSyntaxError when length is negative" do
      -> { @headers.set_range(10, -4) }.should.raise(Net::HTTPHeaderSyntaxError)
    end
  end
end
