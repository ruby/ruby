require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#captures" do
  before do
    @s = StringScanner.new('Fri Dec 12 1975 14:39')
  end

  context "when passed a list of Integers" do
    it "returns an array containing each value given by one of integers" do
      @s.exist?(/(?<wday>\w+) (?<month>\w+) (?<day>\d+)/)
      @s.values_at(0, 1, 2, 3).should == ["Fri Dec 12", "Fri", "Dec", "12"]
    end

    it "returns nil value for any integer that is out of range" do
      @s.exist?(/(?<wday>\w+) (?<month>\w+) (?<day>\d+)/)
      @s.values_at(4).should == [nil]
      @s.values_at(-5).should == [nil]
    end
  end

  context "when passed names" do
    it 'slices captures with the given names' do
      @s.exist?(/(?<wday>\w+) (?<month>\w+) (?<day>\d+)/)
      @s.values_at(:wday, :month, :day).should == ["Fri", "Dec", "12"]
    end

    it 'slices captures with the given String names' do
      @s.exist?(/(?<wday>\w+) (?<month>\w+) (?<day>\d+)/)
      @s.values_at("wday", "month", "day").should == ["Fri", "Dec", "12"]
    end

    it "raises IndexError when given unknown name" do
      @s.exist?(/(?<wday>\w+) (?<month>\w+) (?<day>\d+)/)

      -> {
        @s.values_at("foo")
      }.should raise_error(IndexError, "undefined group name reference: foo")
    end
  end

  it 'supports mixing of names and indices' do
    @s.exist?(/(?<wday>\w+) (?<month>\w+) (?<day>\d+)/)
    @s.values_at(1, "wday", 2, "month", 3, "day").should == ["Fri", "Fri", "Dec", "Dec", "12", "12"]
  end

  it "returns a new empty Array if no arguments given" do
    @s.exist?(/(?<wday>\w+) (?<month>\w+) (?<day>\d+)/)
    @s.values_at().should == []
  end

  it "fails when passed arguments of unsupported types" do
    @s.exist?(/(?<wday>\w+) (?<month>\w+) (?<day>\d+)/)

    -> {
      @s.values_at([])
    }.should raise_error(TypeError, "no implicit conversion of Array into Integer")
  end

  it "returns nil if the most recent matching fails" do
    @s.exist?(/(?<wday>\w+) (?<month>\w+) (?<day>\s+)/)
    @s.values_at(1, 2, 3).should == nil
  end

  it "returns nil if there is no any matching done" do
    @s.values_at(1, 2, 3).should == nil
  end
end
