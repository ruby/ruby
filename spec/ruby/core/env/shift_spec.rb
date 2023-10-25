require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "ENV.shift" do
  before :each do
    @orig = ENV.to_hash
    @external = Encoding.default_external
    @internal = Encoding.default_internal

    Encoding.default_external = Encoding::BINARY
    ENV.replace({"FOO"=>"BAR"})
  end

  after :each do
    Encoding.default_external = @external
    Encoding.default_internal = @internal
    ENV.replace @orig
  end

  it "returns a pair and deletes it" do
    ENV.should.has_key?("FOO")
    pair = ENV.shift
    pair.should == ["FOO", "BAR"]
    ENV.should_not.has_key?("FOO")
  end

  it "returns nil if ENV.empty?" do
    ENV.clear
    ENV.shift.should == nil
  end

  it "uses the locale encoding if Encoding.default_internal is nil" do
    Encoding.default_internal = nil

    pair = ENV.shift
    pair.first.encoding.should equal(ENVSpecs.encoding)
    pair.last.encoding.should equal(ENVSpecs.encoding)
  end

  it "transcodes from the locale encoding to Encoding.default_internal if set" do
    Encoding.default_internal = Encoding::IBM437

    pair = ENV.shift
    pair.first.encoding.should equal(Encoding::IBM437)
    pair.last.encoding.should equal(Encoding::IBM437)
  end
end
