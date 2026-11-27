require_relative '../../spec_helper'

describe "Range#max" do
  it "returns the maximum value in the range" do
    (1..10).max.should == 10
    (1...10).max.should == 9
    (0...2**64).max.should == 18446744073709551615
    ('f'..'l').max.should == 'l'
    ('a'...'f').max.should == 'e'
  end

  it "returns the maximum value in the Float range" do
    (303.20..908.1111).max.should == 908.1111
  end

  it "raises TypeError when called on an exclusive range and a non Integer value" do
    -> { (303.20...908.1111).max }.should.raise(TypeError)
  end

  it "returns nil when the endpoint is less than the start point" do
    (100..10).max.should == nil
    ('z'..'l').max.should == nil
  end

  it "returns nil when the endpoint equals the start point and the range is exclusive" do
    (5...5).max.should == nil
  end

  it "returns the endpoint when the endpoint equals the start point and the range is inclusive" do
    (5..5).max.should.equal?(5)
  end

  it "returns nil when the endpoint is less than the start point in a Float range" do
    (3003.20..908.1111).max.should == nil
  end

  it "returns end point when the range is Time..Time(included end point)" do
    time_start = Time.now
    time_end = Time.now + 1.0
    (time_start..time_end).max.should.equal?(time_end)
  end

  it "raises TypeError when called on a Time...Time(excluded end point)" do
    time_start = Time.now
    time_end = Time.now + 1.0
    -> { (time_start...time_end).max  }.should.raise(TypeError)
  end

  it "raises RangeError when called on an endless range" do
    -> { (1..).max }.should.raise(RangeError)
  end

  it "returns the end point for beginless ranges" do
    (..1).max.should == 1
    (..1.0).max.should == 1.0
  end

  ruby_version_is ""..."4.0" do
    it "raises for an exclusive beginless Integer range" do
      -> {
        (...1).max
      }.should.raise(TypeError, 'cannot exclude end value with non Integer begin value')
    end
  end

  ruby_version_is "4.0" do
    it "returns the end point for exclusive beginless Integer ranges" do
      (...1).max.should == 0
    end
  end

  it "raises for an exclusive beginless non Integer range" do
    -> {
      (...1.0).max
    }.should.raise(TypeError, 'cannot exclude non Integer end value')
  end
end

describe "Range#max given an integer argument" do
  it "returns the n maximum values in the range" do
    (1..10).max(2).should == [10, 9]
    (1...10).max(2).should == [9, 8]
    ('f'..'l').max(2).should == ['l', 'k']
    ('a'...'f').max(2).should == ['e', 'd']
  end

  ruby_version_is "4.0" do
    it "returns the n maximum values in a very large Integer range" do
      (0...2**64).max(2).should == [18446744073709551615, 18446744073709551615-1]
    end
  end

  it "raise a TypeError for non Integer ranges" do
    -> { (303.20..908.1111).max(2) }.should.raise(TypeError)
    -> { (303.20...908.1111).max(2) }.should.raise(TypeError)

    -> { (['a']..['f']).max(2) }.should.raise(TypeError)
    -> { (['a']...['f']).max(2) }.should.raise(TypeError)

    -> { (Time.now..Time.now).max(2) }.should.raise(TypeError)
    -> { (Time.now...Time.now).max(2) }.should.raise(TypeError)
  end

  it "returns [] when the endpoint is less than the start point" do
    (100..10).max(2).should == []
    ('z'..'l').max(2).should == []
  end

  it "returns [] when the endpoint equals the start point and the Integer range is exclusive" do
    (5...5).max(2).should == []
  end

  it "returns the endpoint when the endpoint equals the start point and the Integer range is inclusive" do
    (5..5).max(2).should == [5]
  end

  it "returns all the elements in the range when given n larger that elements count" do
    (1..3).max(10).should == [3, 2, 1]
    (1...3).max(10).should == [2, 1]
  end

  it "raises RangeError when called on an endless range" do
    -> { (1..).max(2) }.should.raise(RangeError)
  end

  ruby_version_is "4.0" do
    it "returns the n maximum values for beginless Integer ranges" do
      (..1).max(2).should == [1, 0]
    end

    it "returns the n maximum values (except the end point) for exclusive beginless Integer ranges" do
      (...1).max(2).should == [0, -1]
    end
  end

  ruby_version_is ""..."4.0" do
    it "raises a RangeError for an beginless non-Integer range" do
      -> { (..1.0).max(2) }.should.raise(RangeError)
      -> { (..'f').max(2) }.should.raise(RangeError)
    end
  end

  ruby_version_is "4.0" do
    it "raises a TypeError for an beginless non-Integer range" do
      -> { (..1.0).max(2) }.should.raise(TypeError)
      -> { (..'f').max(2) }.should.raise(TypeError)
    end
  end

  it "raises an ArgumentError when given negative value" do
    -> { (0..2).max(-1) }.should.raise(ArgumentError)
  end

  it "converts the passed argument to an Integer using #to_int'" do
    obj = mock_int(2)
    (1..10).max(obj).should == [10, 9]
  end

  it "raises a TypeError if the passed argument does not respond to #to_int" do
    -> { (0..2).max(Object.new) }.should.raise(TypeError)
  end

  it "raises a TypeError if #to_int does not return an Integer" do
    obj = mock("to_int")
    obj.should_receive(:to_int).and_return("1")
    -> { (0..2).max(obj) }.should.raise(TypeError)
  end
end

describe "Range#max given a block" do
  it "passes each pair of values in the range to the block" do
    acc = []
    (1..10).max {|a,b| acc << [a,b]; a }
    acc.flatten!
    (1..10).each do |value|
      acc.include?(value).should == true
    end
  end

  it "passes each pair of elements to the block in reversed order" do
    acc = []
    (1..5).max {|a,b| acc << [a,b]; a }
    acc.should == [[2,1],[3,2], [4,3], [5, 4]]
  end

  it "calls #> and #< on the return value of the block" do
    obj = mock('obj')
    obj.should_receive(:>).exactly(2).times
    obj.should_receive(:<).exactly(2).times
    (1..3).max {|a,b| obj }
  end

  it "returns the element the block determines to be the maximum" do
    (1..3).max {|a,b| -3 }.should == 1
  end

  it "returns nil when the endpoint is less than the start point" do
    (100..10).max {|x,y| x <=> y}.should == nil
    ('z'..'l').max {|x,y| x <=> y}.should == nil
    (5...5).max {|x,y| x <=> y}.should == nil
  end

  it "raises RangeError when called with custom comparison method on an beginless range" do
    -> { (..1).max {|a, b| a} }.should.raise(RangeError)
  end
end

describe "Range#max given a block and an integer argument" do
  it "returns n elements the block determines to be the maximum" do
    (1..10).max(2) {|a,b| a <=> b }.should == [10, 9]
  end
end
