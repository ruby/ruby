require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'

describe "Net::HTTPHeader#each_key" do
  before :each do
    @headers = NetHTTPHeaderSpecs::Example.new
    @headers["My-Header"] = "test"
    @headers.add_field("My-Other-Header", "a")
    @headers.add_field("My-Other-Header", "b")
  end

  describe "when passed a block" do
    it "yields each header key to the passed block (keys in lower case)" do
      res = []
      @headers.each_key do |key|
        res << key
      end
      res.sort.should == ["my-header", "my-other-header"]
    end
  end

  describe "when passed no block" do
    it "returns an Enumerator" do
      enumerator = @headers.each_key
      enumerator.should.instance_of?(Enumerator)

      res = []
      enumerator.each do |key|
        res << key
      end
      res.sort.should == ["my-header", "my-other-header"]
    end
  end
end
