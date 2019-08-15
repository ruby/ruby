require_relative '../../spec_helper'
require_relative '../enumerable/shared/enumeratorized'

describe "ENV.delete_if" do
  it "deletes pairs if the block returns true" do
    ENV["foo"] = "bar"
    ENV.delete_if { |k, v| k == "foo" }
    ENV["foo"].should == nil
  end

  it "returns ENV even if nothing deleted" do
    ENV.delete_if { false }.should_not == nil
  end

  it "returns an Enumerator if no block given" do
    ENV.delete_if.should be_an_instance_of(Enumerator)
  end

  it "deletes pairs through enumerator" do
    ENV["foo"] = "bar"
    enum = ENV.delete_if
    enum.each { |k, v| k == "foo" }
    ENV["foo"].should == nil
  end

  it_behaves_like :enumeratorized_with_origin_size, :delete_if, ENV
end
