# -*- encoding: binary -*-
require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "ENV.[]" do
  before :each do
    @variable = "returns_only_frozen_values"
  end

  after :each do
    ENV.delete @variable
  end

  it "returns nil if the variable isn't found" do
    ENV["this_var_is_never_set"].should == nil
  end

  it "returns only frozen values" do
    ENV[@variable] = "a non-frozen string"
    ENV[@variable].should.frozen?
  end

  it "coerces a non-string name with #to_str" do
    ENV[@variable] = "bar"
    k = mock('key')
    k.should_receive(:to_str).and_return(@variable)
    ENV[k].should == "bar"
  end

  it "raises TypeError if the argument is not a String and does not respond to #to_str" do
    -> { ENV[Object.new] }.should raise_error(TypeError, "no implicit conversion of Object into String")
  end

  platform_is :windows do
    it "looks up values case-insensitively" do
      ENV[@variable] = "bar"
      ENV[@variable.upcase].should == "bar"
    end
  end
end

describe "ENV.[]" do
  before :each do
    @variable = "env_element_reference_encoding_specs"

    @external = Encoding.default_external
    @internal = Encoding.default_internal

    Encoding.default_external = Encoding::BINARY
  end

  after :each do
    Encoding.default_external = @external
    Encoding.default_internal = @internal

    ENV.delete @variable
  end

  it "uses the locale encoding if Encoding.default_internal is nil" do
    Encoding.default_internal = nil

    locale = ENVSpecs.encoding
    locale = Encoding::BINARY if locale == Encoding::US_ASCII
    ENV[@variable] = "\xC3\xB8"
    ENV[@variable].encoding.should == locale
  end

  it "transcodes from the locale encoding to Encoding.default_internal if set" do
    # We cannot reliably know the locale encoding, so we merely check that
    # the result string has the expected encoding.
    ENV[@variable] = ""
    Encoding.default_internal = Encoding::IBM437

    ENV[@variable].encoding.should equal(Encoding::IBM437)
  end
end
