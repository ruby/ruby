require_relative '../../spec_helper'
require_relative '../enumerable/shared/enumeratorized'
require_relative 'fixtures/common'

describe "ENV.each_key" do

  it "returns each key" do
    e = []
    orig = ENV.to_hash
    begin
      ENV.clear
      ENV["1"] = "3"
      ENV["2"] = "4"
      ENV.each_key { |k| e << k }.should.equal?(ENV)
      e.should.include?("1")
      e.should.include?("2")
    ensure
      ENV.replace orig
    end
  end

  it "returns an Enumerator if called without a block" do
    enum = ENV.each_key
    enum.should.instance_of?(Enumerator)
    enum.to_a.should == ENV.keys
  end

  it "returns keys in the locale encoding" do
    ENV.each_key do |key|
      key.encoding.should == ENVSpecs.encoding
    end
  end

  it_behaves_like :enumeratorized_with_origin_size, :each_key, ENV
end
