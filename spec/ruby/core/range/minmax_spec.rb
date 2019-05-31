require_relative '../../spec_helper'

describe "Range#minmax" do
  it "returns the minimum and maximum value in the range" do
    (1..10).minmax.should == [1, 10]
    (1...10).minmax.should == [1, 9]
    (0...2**64).minmax.should == [0, 18446744073709551615]
    ('f'..'l').minmax.should == ['f', 'l']
    ('a'...'f').minmax.should == ['a', 'e']
  end

  it "returns the minimum and maximum value in the Float range" do
    (303.20..908.1111).minmax.should == [303.20, 908.1111]
  end

  it "raises TypeError when called on an exclusive range and a non Integer value" do
    lambda { (303.20...908.1111).minmax }.should raise_error(TypeError)
  end

  it "returns nil when the endpoint is less than the start point" do
    (100..10).minmax.should == [nil, nil]
    ('z'..'l').minmax.should == [nil, nil]
  end

  it "returns nil when the endpoint equals the start point and the range is exclusive" do
    (5...5).minmax.should == [nil, nil]
  end

  it "returns the endpoint when the endpoint equals the start point and the range is inclusive" do
    (5..5).minmax.should == [5, 5]
  end

  it "returns nil when the endpoint is less than the start point in a Float range" do
    (3003.20..908.1111).minmax.should == [nil, nil]
  end

  it "returns end point when the range is Time..Time(included end point)" do
    time_start = Time.now
    time_end = Time.now + 1.0
    (time_start..time_end).minmax.should == [time_start, time_end]
  end

  it "raises TypeError when called on a Time...Time(excluded end point)" do
    time_start = Time.now
    time_end = Time.now + 1.0
    lambda { (time_start...time_end).minmax  }.should raise_error(TypeError)
  end
end

describe "Range#minmax given a block" do
  it "passes each pair of values in the range to the block" do
    acc = []
    (1..10).minmax { |a,b| acc << [a,b]; a }
    acc.flatten!
    (1..10).each do |value|
      acc.include?(value).should be_true
    end
  end

  it "returns nil when the endpoint is less than the start point" do
    (100..10).minmax {|x,y| x <=> y}.should == [nil, nil]
    ('z'..'l').minmax {|x,y| x <=> y}.should == [nil, nil]
    (5...5).minmax {|x,y| x <=> y}.should == [nil, nil]
  end
end
