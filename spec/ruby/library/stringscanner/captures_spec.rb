require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#captures" do
  before do
    @s = StringScanner.new('Fri Dec 12 1975 14:39')
  end

  it "returns the array of captured values of the most recent matching" do
    @s.exist?(/(?<wday>\w+) (?<month>\w+) (?<day>\d+)/)
    @s.captures.should == ["Fri", "Dec", "12"]
  end

  it "returns nil if the last match fails" do
    @s.scan(/nope/)
    @s.captures.should == nil
  end

  it "returns nil if there is no any match done" do
    @s.captures.should == nil
  end

  version_is StringScanner::Version, ""..."3.0.8" do # ruby_version_is ""..."3.3.3"
    it "returns '' for an optional capturing group if it doesn't match" do
      @s.exist?(/(?<wday>\w+) (?<month>\w+) (?<day>\s+)?/)
      @s.captures.should == ["Fri", "Dec", ""]
    end
  end

  version_is StringScanner::Version, "3.0.8" do # ruby_version_is "3.3.3"
    it "returns nil for an optional capturing group if it doesn't match" do
      @s.exist?(/(?<wday>\w+) (?<month>\w+) (?<day>\s+)?/)
      @s.captures.should == ["Fri", "Dec", nil]
    end
  end
end
