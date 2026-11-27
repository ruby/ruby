require_relative '../../../spec_helper'
require 'net/http'
require 'stringio'

describe "Net::HTTPResponse#body" do
  before :each do
    @res = Net::HTTPUnknownResponse.new("1.0", "???", "test response")
    @socket = Net::BufferedIO.new(StringIO.new("test body"))
  end

  it "returns the read body" do
    @res.reading_body(@socket, true) do
      @res.body.should == "test body"
    end
  end

  it "returns the previously read body if called a second time" do
    @res.reading_body(@socket, true) do
      @res.body.should.equal?(@res.body)
    end
  end
end
