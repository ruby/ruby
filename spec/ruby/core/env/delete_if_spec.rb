require_relative '../../spec_helper'
require_relative '../enumerable/shared/enumeratorized'

describe "ENV.delete_if" do
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

  it "deletes pairs if the block returns true" do
    ENV.delete_if { |k, v| ["foo", "bar"].include?(k) }
    ENV["foo"].should == nil
    ENV["bar"].should == nil
  end

  it "returns ENV when block given" do
    ENV.delete_if { |k, v| ["foo", "bar"].include?(k) }.should equal(ENV)
  end

  it "returns ENV even if nothing deleted" do
    ENV.delete_if { false }.should equal(ENV)
  end

  it "returns an Enumerator if no block given" do
    ENV.delete_if.should be_an_instance_of(Enumerator)
  end

  it "deletes pairs through enumerator" do
    enum = ENV.delete_if
    enum.each { |k, v| ["foo", "bar"].include?(k) }
    ENV["foo"].should == nil
    ENV["bar"].should == nil
  end

  it "returns ENV from enumerator" do
    enum = ENV.delete_if
    enum.each { |k, v| ["foo", "bar"].include?(k) }.should equal(ENV)
  end

  it "returns ENV from enumerator even if nothing deleted" do
    enum = ENV.delete_if
    enum.each { false }.should equal(ENV)
  end

  it_behaves_like :enumeratorized_with_origin_size, :delete_if, ENV
end
