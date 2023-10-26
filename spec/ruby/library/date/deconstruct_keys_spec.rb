require_relative '../../spec_helper'
require 'date'
date_version = defined?(Date::VERSION) ? Date::VERSION : '3.1.0'

version_is date_version, "3.3" do #ruby_version_is "3.2" do
  describe "Date#deconstruct_keys" do
    it "returns whole hash for nil as an argument" do
      d = Date.new(2022, 10, 5)
      d.deconstruct_keys(nil).should == { year: 2022, month: 10, day: 5, yday: 278, wday: 3 }
    end

    it "returns only specified keys" do
      d = Date.new(2022, 10, 5)
      d.deconstruct_keys([:year, :month]).should == { year: 2022, month: 10 }
    end

    it "requires one argument" do
      -> {
        Date.new(2022, 10, 5).deconstruct_keys
      }.should raise_error(ArgumentError)
    end

    it "it raises error when argument is neither nil nor array" do
      d = Date.new(2022, 10, 5)

      -> { d.deconstruct_keys(1) }.should raise_error(TypeError, "wrong argument type Integer (expected Array or nil)")
      -> { d.deconstruct_keys("asd") }.should raise_error(TypeError, "wrong argument type String (expected Array or nil)")
      -> { d.deconstruct_keys(:x) }.should raise_error(TypeError, "wrong argument type Symbol (expected Array or nil)")
      -> { d.deconstruct_keys({}) }.should raise_error(TypeError, "wrong argument type Hash (expected Array or nil)")
    end

    it "returns {} when passed []" do
      Date.new(2022, 10, 5).deconstruct_keys([]).should == {}
    end

    it "ignores non-Symbol keys" do
      Date.new(2022, 10, 5).deconstruct_keys(['year', []]).should == {}
    end

    it "ignores not existing Symbol keys" do
      Date.new(2022, 10, 5).deconstruct_keys([:year, :a]).should == { year: 2022 }
    end
  end
end
