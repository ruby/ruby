require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'

describe "Net::HTTPHeader#delete when passed key" do
  before :each do
    @headers = NetHTTPHeaderSpecs::Example.new
  end

  it "removes the header entry with the passed key" do
    @headers["My-Header"] = "test"
    @headers.delete("My-Header")

    @headers["My-Header"].should be_nil
    @headers.size.should eql(0)
  end

  it "returns the removed values" do
    @headers["My-Header"] = "test"
    @headers.delete("My-Header").should == ["test"]
  end

  it "is case-insensitive" do
    @headers["My-Header"] = "test"
    @headers.delete("my-header")

    @headers["My-Header"].should be_nil
    @headers.size.should eql(0)
  end
end
