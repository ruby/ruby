require_relative '../../spec_helper'
require_relative '../enumerable/shared/enumeratorized'

describe "ENV.keep_if" do
  before :each do
    @foo = ENV["foo"]
    @bar = ENV["bar"]

    ENV["foo"] = "0"
    ENV["bar"] = "1"
  end

  after :each do
    ENV["foo"] = @foo
    ENV["bar"] = @bar
  end

  it "deletes pairs if the block returns false" do
    ENV.keep_if { |k, v| !["foo", "bar"].include?(k) }
    ENV["foo"].should == nil
    ENV["bar"].should == nil
  end

  it "returns ENV when block given" do
    ENV.keep_if { |k, v| !["foo", "bar"].include?(k) }.should equal(ENV)
  end

  it "returns ENV even if nothing deleted" do
    ENV.keep_if { true }.should equal(ENV)
  end

  it "returns an Enumerator if no block given" do
    ENV.keep_if.should be_an_instance_of(Enumerator)
  end

  it "deletes pairs through enumerator" do
    enum = ENV.keep_if
    enum.each { |k, v| !["foo", "bar"].include?(k) }
    ENV["foo"].should == nil
    ENV["bar"].should == nil
  end

  it "returns ENV from enumerator" do
    enum = ENV.keep_if
    enum.each { |k, v| !["foo", "bar"].include?(k) }.should equal(ENV)
  end

  it "returns ENV from enumerator even if nothing deleted" do
    enum = ENV.keep_if
    enum.each { true }.should equal(ENV)
  end

  it_behaves_like :enumeratorized_with_origin_size, :keep_if, ENV
end
