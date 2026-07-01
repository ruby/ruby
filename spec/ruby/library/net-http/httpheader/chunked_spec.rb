require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'

describe "Net::HTTPHeader#chunked?" do
  before :each do
    @headers = NetHTTPHeaderSpecs::Example.new
  end

  it "returns true if the 'Transfer-Encoding' header entry is set to chunked" do
    @headers.chunked?.should == false

    @headers["Transfer-Encoding"] = "bla"
    @headers.chunked?.should == false

    @headers["Transfer-Encoding"] = "blachunkedbla"
    @headers.chunked?.should == false

    @headers["Transfer-Encoding"] = "chunked"
    @headers.chunked?.should == true
  end
end
