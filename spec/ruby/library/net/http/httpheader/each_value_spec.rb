require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'

describe "Net::HTTPHeader#each_value" do
  before :each do
    @headers = NetHTTPHeaderSpecs::Example.new
    @headers["My-Header"] = "test"
    @headers.add_field("My-Other-Header", "a")
    @headers.add_field("My-Other-Header", "b")
  end

  describe "when passed a block" do
    it "yields each header entry's joined values" do
      res = []
      @headers.each_value do |value|
        res << value
      end
      res.sort.should == ["a, b", "test"]
    end
  end

  describe "when passed no block" do
    it "returns an Enumerator" do
      enumerator = @headers.each_value
      enumerator.should be_an_instance_of(Enumerator)

      res = []
      enumerator.each do |key|
        res << key
      end
      res.sort.should == ["a, b", "test"]
    end
  end
end
