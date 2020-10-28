require_relative '../../spec_helper'
require_relative '../enumerable/shared/enumeratorized'

describe "ENV.reject!" do
  before :each do
    @foo = ENV["foo"]
  end

  after :each do
    ENV["foo"] = @foo
  end

  it "rejects entries based on key" do
    ENV["foo"] = "bar"
    ENV.reject! { |k, v| k == "foo" }
    ENV["foo"].should == nil
  end

  it "rejects entries based on value" do
    ENV["foo"] = "bar"
    ENV.reject! { |k, v| v == "bar" }
    ENV["foo"].should == nil
  end

  it "returns itself or nil" do
    ENV.reject! { false }.should == nil
    ENV["foo"] = "bar"
    ENV.reject! { |k, v| k == "foo" }.should equal(ENV)
    ENV["foo"].should == nil
  end

  it "returns an Enumerator if called without a block" do
    ENV["foo"] = "bar"
    enum = ENV.reject!
    enum.should be_an_instance_of(Enumerator)
    enum.each { |k, v| k == "foo" }.should equal(ENV)
    ENV["foo"].should == nil
  end

  it "doesn't raise if empty" do
    orig = ENV.to_hash
    begin
      ENV.clear
      -> { ENV.reject! }.should_not raise_error(LocalJumpError)
    ensure
      ENV.replace orig
    end
  end

  it_behaves_like :enumeratorized_with_origin_size, :reject!, ENV
end

describe "ENV.reject" do
  before :each do
    @foo = ENV["foo"]
  end

  after :each do
    ENV["foo"] = @foo
  end

  it "rejects entries based on key" do
    ENV["foo"] = "bar"
    e = ENV.reject { |k, v| k == "foo" }
    e["foo"].should == nil
    ENV["foo"].should == "bar"
    ENV["foo"] = nil
  end

  it "rejects entries based on value" do
    ENV["foo"] = "bar"
    e = ENV.reject { |k, v| v == "bar" }
    e["foo"].should == nil
    ENV["foo"].should == "bar"
    ENV["foo"] = nil
  end

  it "returns a Hash" do
    ENV.reject { false }.should be_kind_of(Hash)
  end

  it "returns an Enumerator if called without a block" do
    ENV["foo"] = "bar"
    enum = ENV.reject
    enum.should be_an_instance_of(Enumerator)
    enum.each { |k, v| k == "foo"}
    ENV["foo"] = nil
  end

  it "doesn't raise if empty" do
    orig = ENV.to_hash
    begin
      ENV.clear
      -> { ENV.reject }.should_not raise_error(LocalJumpError)
    ensure
      ENV.replace orig
    end
  end

  it_behaves_like :enumeratorized_with_origin_size, :reject, ENV
end
