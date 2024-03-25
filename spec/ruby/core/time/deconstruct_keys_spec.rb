require_relative '../../spec_helper'

ruby_version_is "3.2" do
  describe "Time#deconstruct_keys" do
    it "returns whole hash for nil as an argument" do
      d = Time.utc(2022, 10, 5, 13, 30)
      res = { year: 2022, month: 10, day: 5, yday: 278, wday: 3, hour: 13,
              min: 30, sec: 0, subsec: 0, dst: false, zone: "UTC" }
      d.deconstruct_keys(nil).should == res
    end

    it "returns only specified keys" do
      d = Time.utc(2022, 10, 5, 13, 39)
      d.deconstruct_keys([:zone, :subsec]).should == { zone: "UTC", subsec: 0 }
    end

    it "requires one argument" do
      -> {
        Time.new(2022, 10, 5, 13, 30).deconstruct_keys
      }.should raise_error(ArgumentError)
    end

    it "it raises error when argument is neither nil nor array" do
      d = Time.new(2022, 10, 5, 13, 30)

      -> { d.deconstruct_keys(1) }.should raise_error(TypeError, "wrong argument type Integer (expected Array or nil)")
      -> { d.deconstruct_keys("asd") }.should raise_error(TypeError, "wrong argument type String (expected Array or nil)")
      -> { d.deconstruct_keys(:x) }.should raise_error(TypeError, "wrong argument type Symbol (expected Array or nil)")
      -> { d.deconstruct_keys({}) }.should raise_error(TypeError, "wrong argument type Hash (expected Array or nil)")
    end

    it "returns {} when passed []" do
      Time.new(2022, 10, 5, 13, 30).deconstruct_keys([]).should == {}
    end

    it "ignores non-Symbol keys" do
      Time.new(2022, 10, 5, 13, 30).deconstruct_keys(['year', []]).should == {}
    end

    it "ignores not existing Symbol keys and processes keys after the first non-existing one" do
      d = Time.utc(2022, 10, 5, 13, 30)
      d.deconstruct_keys([:year, :a, :month, :b, :day]).should == { year: 2022, month: 10, day: 5 }
    end
  end
end
