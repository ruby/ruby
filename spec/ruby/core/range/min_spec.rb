require_relative '../../spec_helper'

describe "Range#min" do
  it "returns the minimum value in the range" do
    (1..10).min.should == 1
    ('f'..'l').min.should == 'f'
  end

  it "returns the minimum value in the Float range" do
    (303.20..908.1111).min.should == 303.20
  end

  it "returns nil when the start point is greater than the endpoint" do
    (100..10).min.should == nil
    ('z'..'l').min.should == nil
  end

  it "returns nil when the endpoint equals the start point and the range is exclusive" do
    (7...7).min.should == nil
  end

  it "returns the start point when the endpoint equals the start point and the range is inclusive" do
    (7..7).min.should.equal?(7)
  end

  it "returns nil when the start point is greater than the endpoint in a Float range" do
    (3003.20..908.1111).min.should == nil
  end

  it "returns start point when the range is Time..Time(included end point)" do
    time_start = Time.now
    time_end = Time.now + 1.0
    (time_start..time_end).min.should.equal?(time_start)
  end

  it "returns start point when the range is Time...Time(excluded end point)" do
    time_start = Time.now
    time_end = Time.now + 1.0
    (time_start...time_end).min.should.equal?(time_start)
  end

  it "returns the start point for endless ranges" do
    (1..).min.should == 1
    (1.0...).min.should == 1.0
  end

  it "raises RangeError when called on an beginless range" do
    -> { (..1).min }.should.raise(RangeError)
  end
end

describe "Range#min given an integer argument" do
  it "returns the n minimum values in the range" do
    (1..10).min(2).should == [1, 2]
    (1...10).min(2).should == [1, 2]
    (0...2**64).min(2).should == [0, 1]
    ('f'..'l').min(2).should == ['f', 'g']
    ('a'...'f').min(2).should == ['a', 'b']
  end

  it "raise a TypeError for non Integer ranges" do
    -> { (303.20..908.1111).min(2) }.should.raise(TypeError)
    -> { (303.20...908.1111).min(2) }.should.raise(TypeError)

    -> { (['a']..['f']).min(2) }.should.raise(TypeError)
    -> { (['a']...['f']).min(2) }.should.raise(TypeError)

    -> { (Time.now..Time.now).min(2) }.should.raise(TypeError)
    -> { (Time.now...Time.now).min(2) }.should.raise(TypeError)
  end

  it "returns [] when the endpoint is less than the start point" do
    (100..10).min(2).should == []
    ('z'..'l').min(2).should == []
  end

  it "returns [] when the endpoint equals the start point and the Integer range is exclusive" do
    (5...5).min(2).should == []
  end

  it "returns the endpoint when the endpoint equals the start point and the Integer range is inclusive" do
    (5..5).min(2).should == [5]
  end

  it "returns all the elements in the range when given n larger that elements count" do
    (1..3).min(10).should == [1, 2, 3]
    (1...3).min(10).should == [1, 2]
  end

  it "raises RangeError when called on a beginless range" do
    -> { (..1).min(2) }.should.raise(RangeError)
    -> { (...1).min(2) }.should.raise(RangeError)
  end

  it "returns the n minimum values for endless Integer ranges" do
    (1..).min(2).should == [1, 2]
    (1...).min(2).should == [1, 2]
  end

  it "raises a TypeError for an endless non-Integer range" do
    -> { (1.0..).min(2) }.should.raise(TypeError)
  end

  it "raises an ArgumentError when given negative value" do
    -> { (0..2).min(-1) }.should.raise(ArgumentError)
  end

  it "converts the passed argument to an Integer using #to_int" do
    obj = mock_int(2)
    (1..10).min(obj).should == [1, 2]
  end

  it "raises a TypeError if the passed argument does not respond to #to_int" do
    -> { (0..2).min(Object.new) }.should.raise(TypeError)
  end

  it "raises a TypeError if #to_int does not return an Integer" do
    obj = mock("to_int")
    obj.should_receive(:to_int).and_return("1")
    -> { (0..2).min(obj) }.should.raise(TypeError)
  end
end

describe "Range#min given a block" do
  it "passes each pair of values in the range to the block" do
    acc = []
    (1..10).min {|a,b| acc << [a,b]; a }
    acc.flatten!
    (1..10).each do |value|
      acc.include?(value).should == true
    end
  end

  it "passes each pair of elements to the block where the first argument is the current element, and the last is the first element" do
    acc = []
    (1..5).min {|a,b| acc << [a,b]; a }
    acc.should == [[2, 1], [3, 1], [4, 1], [5, 1]]
  end

  it "calls #> and #< on the return value of the block" do
    obj = mock('obj')
    obj.should_receive(:>).exactly(2).times
    obj.should_receive(:<).exactly(2).times
    (1..3).min {|a,b| obj }
  end

  it "returns the element the block determines to be the minimum" do
    (1..3).min {|a,b| -3 }.should == 3
  end

  it "returns nil when the start point is greater than the endpoint" do
    (100..10).min {|x,y| x <=> y}.should == nil
    ('z'..'l').min {|x,y| x <=> y}.should == nil
    (7...7).min {|x,y| x <=> y}.should == nil
  end

  it "raises RangeError when called with custom comparison method on an endless range" do
    -> { (1..).min {|a, b| a} }.should.raise(RangeError)
  end
end

describe "Range#max given a block and an integer argument" do
  it "returns n elements the block determines to be the minimum" do
    (1..10).min(2) { |a,b| a <=> b }.should == [1, 2]
  end
end
