require_relative '../../spec_helper'
require_relative '../enumerable/shared/enumeratorized'

describe "ENV.select!" do
  it_behaves_like :enumeratorized_with_origin_size, :select!, ENV

  before :each do
    @saved_foo = ENV["foo"]
  end

  after :each do
    ENV["foo"] = @saved_foo
  end

  it "removes environment variables for which the block returns false" do
    ENV["foo"] = "bar"
    ENV.select! { |k, v| k != "foo" }
    ENV["foo"].should == nil
  end

  it "returns self if any changes were made" do
    ENV["foo"] = "bar"
    (ENV.select! { |k, v| k != "foo" }).should == ENV
  end

  it "returns nil if no changes were made" do
    (ENV.select! { true }).should == nil
  end

  it "returns an Enumerator if called without a block" do
    ENV.select!.should.instance_of?(Enumerator)
  end

  it "selects via the enumerator" do
    enum = ENV.select!
    ENV["foo"] = "bar"
    enum.each { |k, v| k != "foo" }
    ENV["foo"].should == nil
  end
end

describe "ENV.select" do
  it_behaves_like :enumeratorized_with_origin_size, :select, ENV

  before :each do
    @saved_foo = ENV["foo"]
  end

  after :each do
    ENV["foo"] = @saved_foo
  end

  it "returns a Hash of names and values for which block returns true" do
    ENV["foo"] = "bar"
    (ENV.select { |k, v| k == "foo" }).should == { "foo" => "bar" }
  end

  it "returns an Enumerator when no block is given" do
    enum = ENV.select
    enum.should.instance_of?(Enumerator)
  end

  it "selects via the enumerator" do
    enum = ENV.select
    ENV["foo"] = "bar"
    enum.each { |k, v| k == "foo" }.should == { "foo" => "bar"}
  end
end
