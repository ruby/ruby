require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'

describe "Net::HTTPHeader#size" do
  before :each do
    @headers = NetHTTPHeaderSpecs::Example.new
  end

  it "returns the number of header entries in self" do
    @headers.size.should.eql?(0)

    @headers["a"] = "b"
    @headers.size.should.eql?(1)

    @headers["b"] = "b"
    @headers.size.should.eql?(2)

    @headers["c"] = "c"
    @headers.size.should.eql?(3)
  end
end
