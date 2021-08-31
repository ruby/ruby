require_relative 'spec_helper'
require_relative '../enumerable/shared/enumeratorized'

describe "ENV.each_value" do

  it "returns each value" do
    e = []
    orig = ENV.to_hash
    begin
      ENV.clear
      ENV["1"] = "3"
      ENV["2"] = "4"
      ENV.each_value { |v| e << v }.should equal(ENV)
      e.should include("3")
      e.should include("4")
    ensure
      ENV.replace orig
    end
  end

  it "returns an Enumerator if called without a block" do
    enum = ENV.each_value
    enum.should be_an_instance_of(Enumerator)
    enum.to_a.should == ENV.values
  end

  it "uses the locale encoding" do
    ENV.each_value do |value|
      value.should.be_locale_env
    end
  end

  it_behaves_like :enumeratorized_with_origin_size, :each_value, ENV
end
