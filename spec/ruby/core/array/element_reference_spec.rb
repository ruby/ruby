require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Array#[]" do
  it "returns the element at index with [index]" do
    [ "a", "b", "c", "d", "e" ][1].should == "b"

    a = [1, 2, 3, 4]

    a[0].should == 1
    a[1].should == 2
    a[2].should == 3
    a[3].should == 4
    a[4].should == nil
    a[10].should == nil

    a.should == [1, 2, 3, 4]
  end

  it "returns the element at index from the end of the array with [-index]" do
    [ "a", "b", "c", "d", "e" ][-2].should == "d"

    a = [1, 2, 3, 4]

    a[-1].should == 4
    a[-2].should == 3
    a[-3].should == 2
    a[-4].should == 1
    a[-5].should == nil
    a[-10].should == nil

    a.should == [1, 2, 3, 4]
  end

  it "returns count elements starting from index with [index, count]" do
    [ "a", "b", "c", "d", "e" ][2, 3].should == ["c", "d", "e"]

    a = [1, 2, 3, 4]

    a[0, 0].should == []
    a[0, 1].should == [1]
    a[0, 2].should == [1, 2]
    a[0, 4].should == [1, 2, 3, 4]
    a[0, 6].should == [1, 2, 3, 4]
    a[0, -1].should == nil
    a[0, -2].should == nil
    a[0, -4].should == nil

    a[2, 0].should == []
    a[2, 1].should == [3]
    a[2, 2].should == [3, 4]
    a[2, 4].should == [3, 4]
    a[2, -1].should == nil

    a[4, 0].should == []
    a[4, 2].should == []
    a[4, -1].should == nil

    a[5, 0].should == nil
    a[5, 2].should == nil
    a[5, -1].should == nil

    a[6, 0].should == nil
    a[6, 2].should == nil
    a[6, -1].should == nil

    a.should == [1, 2, 3, 4]
  end

  it "returns count elements starting at index from the end of array with [-index, count]" do
    [ "a", "b", "c", "d", "e" ][-2, 2].should == ["d", "e"]

    a = [1, 2, 3, 4]

    a[-1, 0].should == []
    a[-1, 1].should == [4]
    a[-1, 2].should == [4]
    a[-1, -1].should == nil

    a[-2, 0].should == []
    a[-2, 1].should == [3]
    a[-2, 2].should == [3, 4]
    a[-2, 4].should == [3, 4]
    a[-2, -1].should == nil

    a[-4, 0].should == []
    a[-4, 1].should == [1]
    a[-4, 2].should == [1, 2]
    a[-4, 4].should == [1, 2, 3, 4]
    a[-4, 6].should == [1, 2, 3, 4]
    a[-4, -1].should == nil

    a[-5, 0].should == nil
    a[-5, 1].should == nil
    a[-5, 10].should == nil
    a[-5, -1].should == nil

    a.should == [1, 2, 3, 4]
  end

  it "returns the first count elements with [0, count]" do
    [ "a", "b", "c", "d", "e" ][0, 3].should == ["a", "b", "c"]
  end

  it "returns the subarray which is independent to self with [index,count]" do
    a = [1, 2, 3]
    sub = a[1, 2]
    sub.replace([:a, :b])
    a.should == [1, 2, 3]
  end

  it "tries to convert the passed argument to an Integer using #to_int" do
    obj = mock('to_int')
    obj.stub!(:to_int).and_return(2)

    a = [1, 2, 3, 4]
    a[obj].should == 3
    a[obj, 1].should == [3]
    a[obj, obj].should == [3, 4]
    a[0, obj].should == [1, 2]
  end

  it "raises TypeError if to_int returns non-integer" do
    from = mock('from')
    to = mock('to')

    # So we can construct a range out of them...
    def from.<=>(o) 0 end
    def to.<=>(o) 0 end

    a = [1, 2, 3, 4, 5]

    def from.to_int() 'cat' end
    def to.to_int() -2 end

    -> { a[from..to] }.should.raise(TypeError)

    def from.to_int() 1 end
    def to.to_int() 'cat' end

    -> { a[from..to] }.should.raise(TypeError)
  end

  it "returns the elements specified by Range indexes with [m..n]" do
    [ "a", "b", "c", "d", "e" ][1..3].should == ["b", "c", "d"]
    [ "a", "b", "c", "d", "e" ][4..-1].should == ['e']
    [ "a", "b", "c", "d", "e" ][3..3].should == ['d']
    [ "a", "b", "c", "d", "e" ][3..-2].should == ['d']
    ['a'][0..-1].should == ['a']

    a = [1, 2, 3, 4]

    a[0..-10].should == []
    a[0..0].should == [1]
    a[0..1].should == [1, 2]
    a[0..2].should == [1, 2, 3]
    a[0..3].should == [1, 2, 3, 4]
    a[0..4].should == [1, 2, 3, 4]
    a[0..10].should == [1, 2, 3, 4]

    a[2..-10].should == []
    a[2..0].should == []
    a[2..2].should == [3]
    a[2..3].should == [3, 4]
    a[2..4].should == [3, 4]

    a[3..0].should == []
    a[3..3].should == [4]
    a[3..4].should == [4]

    a[4..0].should == []
    a[4..4].should == []
    a[4..5].should == []

    a[5..0].should == nil
    a[5..5].should == nil
    a[5..6].should == nil

    a.should == [1, 2, 3, 4]
  end

  it "returns elements specified by Range indexes except the element at index n with [m...n]" do
    [ "a", "b", "c", "d", "e" ][1...3].should == ["b", "c"]

    a = [1, 2, 3, 4]

    a[0...-10].should == []
    a[0...0].should == []
    a[0...1].should == [1]
    a[0...2].should == [1, 2]
    a[0...3].should == [1, 2, 3]
    a[0...4].should == [1, 2, 3, 4]
    a[0...10].should == [1, 2, 3, 4]

    a[2...-10].should == []
    a[2...0].should == []
    a[2...2].should == []
    a[2...3].should == [3]
    a[2...4].should == [3, 4]

    a[3...0].should == []
    a[3...3].should == []
    a[3...4].should == [4]

    a[4...0].should == []
    a[4...4].should == []
    a[4...5].should == []

    a[5...0].should == nil
    a[5...5].should == nil
    a[5...6].should == nil

    a.should == [1, 2, 3, 4]
  end

  it "returns elements that exist if range start is in the array but range end is not with [m..n]" do
    [ "a", "b", "c", "d", "e" ][4..7].should == ["e"]
  end

  it "accepts Range instances having a negative m and both signs for n with [m..n] and [m...n]" do
    a = [1, 2, 3, 4]

    a[-1..-1].should == [4]
    a[-1...-1].should == []
    a[-1..3].should == [4]
    a[-1...3].should == []
    a[-1..4].should == [4]
    a[-1...4].should == [4]
    a[-1..10].should == [4]
    a[-1...10].should == [4]
    a[-1..0].should == []
    a[-1..-4].should == []
    a[-1...-4].should == []
    a[-1..-6].should == []
    a[-1...-6].should == []

    a[-2..-2].should == [3]
    a[-2...-2].should == []
    a[-2..-1].should == [3, 4]
    a[-2...-1].should == [3]
    a[-2..10].should == [3, 4]
    a[-2...10].should == [3, 4]

    a[-4..-4].should == [1]
    a[-4..-2].should == [1, 2, 3]
    a[-4...-2].should == [1, 2]
    a[-4..-1].should == [1, 2, 3, 4]
    a[-4...-1].should == [1, 2, 3]
    a[-4..3].should == [1, 2, 3, 4]
    a[-4...3].should == [1, 2, 3]
    a[-4..4].should == [1, 2, 3, 4]
    a[-4...4].should == [1, 2, 3, 4]
    a[-4...4].should == [1, 2, 3, 4]
    a[-4..0].should == [1]
    a[-4...0].should == []
    a[-4..1].should == [1, 2]
    a[-4...1].should == [1]

    a[-5..-5].should == nil
    a[-5...-5].should == nil
    a[-5..-4].should == nil
    a[-5..-1].should == nil
    a[-5..10].should == nil

    a.should == [1, 2, 3, 4]
  end

  it "returns the subarray which is independent to self with [m..n]" do
    a = [1, 2, 3]
    sub = a[1..2]
    sub.replace([:a, :b])
    a.should == [1, 2, 3]
  end

  it "tries to convert Range elements to Integers using #to_int with [m..n] and [m...n]" do
    from = mock('from')
    to = mock('to')

    # So we can construct a range out of them...
    def from.<=>(o) 0 end
    def to.<=>(o) 0 end

    def from.to_int() 1 end
    def to.to_int() -2 end

    a = [1, 2, 3, 4]

    a[from..to].should == [2, 3]
    a[from...to].should == [2]
    a[1..0].should == []
    a[1...0].should == []

    -> { a["a" .. "b"] }.should.raise(TypeError)
    -> { a["a" ... "b"] }.should.raise(TypeError)
    -> { a[from .. "b"] }.should.raise(TypeError)
    -> { a[from ... "b"] }.should.raise(TypeError)
  end

  it "returns the same elements as [m..n] and [m...n] with Range subclasses" do
    a = [1, 2, 3, 4]
    range_incl = ArraySpecs::MyRange.new(1, 2)
    range_excl = ArraySpecs::MyRange.new(-3, -1, true)

    a[range_incl].should == [2, 3]
    a[range_excl].should == [2, 3]
  end

  it "returns nil for a requested index not in the array with [index]" do
    [ "a", "b", "c", "d", "e" ][5].should == nil
  end

  it "returns [] if the index is valid but length is zero with [index, length]" do
    [ "a", "b", "c", "d", "e" ][0, 0].should == []
    [ "a", "b", "c", "d", "e" ][2, 0].should == []
  end

  it "returns nil if length is zero but index is invalid with [index, length]" do
    [ "a", "b", "c", "d", "e" ][100, 0].should == nil
    [ "a", "b", "c", "d", "e" ][-50, 0].should == nil
  end

  # This is by design. It is in the official documentation.
  it "returns [] if index == array.size with [index, length]" do
    %w|a b c d e|[5, 2].should == []
  end

  it "returns nil if index > array.size with [index, length]" do
    %w|a b c d e|[6, 2].should == nil
  end

  it "returns nil if length is negative with [index, length]" do
    %w|a b c d e|[3, -1].should == nil
    %w|a b c d e|[2, -2].should == nil
    %w|a b c d e|[1, -100].should == nil
  end

  it "returns nil if no requested index is in the array with [m..n]" do
    [ "a", "b", "c", "d", "e" ][6..10].should == nil
  end

  it "returns nil if range start is not in the array with [m..n]" do
    [ "a", "b", "c", "d", "e" ][-10..2].should == nil
    [ "a", "b", "c", "d", "e" ][10..12].should == nil
  end

  it "returns an empty array when m == n with [m...n]" do
    [1, 2, 3, 4, 5][1...1].should == []
  end

  it "returns an empty array with [0...0]" do
    [1, 2, 3, 4, 5][0...0].should == []
  end

  it "returns a subarray where m, n negatives and m < n with [m..n]" do
    [ "a", "b", "c", "d", "e" ][-3..-2].should == ["c", "d"]
  end

  it "returns an array containing the first element with [0..0]" do
    [1, 2, 3, 4, 5][0..0].should == [1]
  end

  it "returns the entire array with [0..-1]" do
    [1, 2, 3, 4, 5][0..-1].should == [1, 2, 3, 4, 5]
  end

  it "returns all but the last element with [0...-1]" do
    [1, 2, 3, 4, 5][0...-1].should == [1, 2, 3, 4]
  end

  it "returns [3] for [2..-1] out of [1, 2, 3]" do
    [1,2,3][2..-1].should == [3]
  end

  it "returns an empty array when m > n and m, n are positive with [m..n]" do
    [1, 2, 3, 4, 5][3..2].should == []
  end

  it "returns an empty array when m > n and m, n are negative with [m..n]" do
    [1, 2, 3, 4, 5][-2..-3].should == []
  end

  it "does not expand array when the indices are outside of the array bounds" do
    a = [1, 2]
    a[4].should == nil
    a.should == [1, 2]
    a[4, 0].should == nil
    a.should == [1, 2]
    a[6, 1].should == nil
    a.should == [1, 2]
    a[8...8].should == nil
    a.should == [1, 2]
    a[10..10].should == nil
    a.should == [1, 2]
  end

  describe "with a subclass of Array" do
    before :each do
      ScratchPad.clear

      @array = ArraySpecs::MyArray[1, 2, 3, 4, 5]
    end

    it "returns a Array instance with [n, m]" do
      @array[0, 2].should.instance_of?(Array)
    end

    it "returns a Array instance with [-n, m]" do
      @array[-3, 2].should.instance_of?(Array)
    end

    it "returns a Array instance with [n..m]" do
      @array[1..3].should.instance_of?(Array)
    end

    it "returns a Array instance with [n...m]" do
      @array[1...3].should.instance_of?(Array)
    end

    it "returns a Array instance with [-n..-m]" do
      @array[-3..-1].should.instance_of?(Array)
    end

    it "returns a Array instance with [-n...-m]" do
      @array[-3...-1].should.instance_of?(Array)
    end

    it "returns an empty array when m == n with [m...n]" do
      @array[1...1].should == []
      ScratchPad.recorded.should == nil
    end

    it "returns an empty array with [0...0]" do
      @array[0...0].should == []
      ScratchPad.recorded.should == nil
    end

    it "returns an empty array when m > n and m, n are positive with [m..n]" do
      @array[3..2].should == []
      ScratchPad.recorded.should == nil
    end

    it "returns an empty array when m > n and m, n are negative with [m..n]" do
      @array[-2..-3].should == []
      ScratchPad.recorded.should == nil
    end

    it "returns [] if index == array.size with [index, length]" do
      @array[5, 2].should == []
      ScratchPad.recorded.should == nil
    end

    it "returns [] if the index is valid but length is zero with [index, length]" do
      @array[0, 0].should == []
      @array[2, 0].should == []
      ScratchPad.recorded.should == nil
    end

    it "does not call #initialize on the subclass instance" do
      @array[0, 3].should == [1, 2, 3]
      ScratchPad.recorded.should == nil
    end
  end

  it "raises a RangeError when the start index is out of range of Fixnum" do
    array = [1, 2, 3, 4, 5, 6]
    obj = mock('large value')
    obj.should_receive(:to_int).and_return(bignum_value)
    -> { array[obj] }.should.raise(RangeError)

    obj = 8e19
    -> { array[obj] }.should.raise(RangeError)

    # boundary value when longs are 64 bits
    -> { array[2.0**63] }.should.raise(RangeError)

    # just under the boundary value when longs are 64 bits
    array[max_long.to_f.prev_float].should == nil
  end

  it "raises a RangeError when the length is out of range of Fixnum" do
    array = [1, 2, 3, 4, 5, 6]
    obj = mock('large value')
    obj.should_receive(:to_int).and_return(bignum_value)
    -> { array[1, obj] }.should.raise(RangeError)

    obj = 8e19
    -> { array[1, obj] }.should.raise(RangeError)
  end

  it "raises a type error if a range is passed with a length" do
    ->{ [1, 2, 3][1..2, 1] }.should.raise(TypeError)
  end

  it "raises a RangeError if passed a range with a bound that is too large" do
    array = [1, 2, 3, 4, 5, 6]
    -> { array[bignum_value..(bignum_value + 1)] }.should.raise(RangeError)
    -> { array[0..bignum_value] }.should.raise(RangeError)
  end

  it "can accept endless ranges" do
    a = [0, 1, 2, 3, 4, 5]
    a[eval("(2..)")].should == [2, 3, 4, 5]
    a[eval("(2...)")].should == [2, 3, 4, 5]
    a[eval("(-2..)")].should == [4, 5]
    a[eval("(-2...)")].should == [4, 5]
    a[eval("(9..)")].should == nil
    a[eval("(9...)")].should == nil
    a[eval("(-9..)")].should == nil
    a[eval("(-9...)")].should == nil
  end

  describe "can be sliced with Enumerator::ArithmeticSequence" do
    before :each do
      @array = [0, 1, 2, 3, 4, 5]
    end

    it "has endless range and positive steps" do
      @array[eval("(0..).step(1)")].should == [0, 1, 2, 3, 4, 5]
      @array[eval("(0..).step(2)")].should == [0, 2, 4]
      @array[eval("(0..).step(10)")].should == [0]

      @array[eval("(2..).step(1)")].should == [2, 3, 4, 5]
      @array[eval("(2..).step(2)")].should == [2, 4]
      @array[eval("(2..).step(10)")].should == [2]

      @array[eval("(-3..).step(1)")].should == [3, 4, 5]
      @array[eval("(-3..).step(2)")].should == [3, 5]
      @array[eval("(-3..).step(10)")].should == [3]
    end

    it "has beginless range and positive steps" do
      # end with zero index
      @array[(..0).step(1)].should == [0]
      @array[(...0).step(1)].should == []

      @array[(..0).step(2)].should == [0]
      @array[(...0).step(2)].should == []

      @array[(..0).step(10)].should == [0]
      @array[(...0).step(10)].should == []

      # end with positive index
      @array[(..3).step(1)].should == [0, 1, 2, 3]
      @array[(...3).step(1)].should == [0, 1, 2]

      @array[(..3).step(2)].should == [0, 2]
      @array[(...3).step(2)].should == [0, 2]

      @array[(..3).step(10)].should == [0]
      @array[(...3).step(10)].should == [0]

      # end with negative index
      @array[(..-2).step(1)].should == [0, 1, 2, 3, 4,]
      @array[(...-2).step(1)].should == [0, 1, 2, 3]

      @array[(..-2).step(2)].should == [0, 2, 4]
      @array[(...-2).step(2)].should == [0, 2]

      @array[(..-2).step(10)].should == [0]
      @array[(...-2).step(10)].should == [0]
    end

    it "has endless range and negative steps" do
      @array[eval("(0..).step(-1)")].should == [0]
      @array[eval("(0..).step(-2)")].should == [0]
      @array[eval("(0..).step(-10)")].should == [0]

      @array[eval("(2..).step(-1)")].should == [2, 1, 0]
      @array[eval("(2..).step(-2)")].should == [2, 0]

      @array[eval("(-3..).step(-1)")].should == [3, 2, 1, 0]
      @array[eval("(-3..).step(-2)")].should == [3, 1]
    end

    it "has closed range and positive steps" do
      # start and end with 0
      @array[eval("(0..0).step(1)")].should == [0]
      @array[eval("(0...0).step(1)")].should == []

      @array[eval("(0..0).step(2)")].should == [0]
      @array[eval("(0...0).step(2)")].should == []

      @array[eval("(0..0).step(10)")].should == [0]
      @array[eval("(0...0).step(10)")].should == []

      # start and end with positive index
      @array[eval("(1..3).step(1)")].should == [1, 2, 3]
      @array[eval("(1...3).step(1)")].should == [1, 2]

      @array[eval("(1..3).step(2)")].should == [1, 3]
      @array[eval("(1...3).step(2)")].should == [1]

      @array[eval("(1..3).step(10)")].should == [1]
      @array[eval("(1...3).step(10)")].should == [1]

      # start with positive index, end with negative index
      @array[eval("(1..-2).step(1)")].should == [1, 2, 3, 4]
      @array[eval("(1...-2).step(1)")].should == [1, 2, 3]

      @array[eval("(1..-2).step(2)")].should ==  [1, 3]
      @array[eval("(1...-2).step(2)")].should ==  [1, 3]

      @array[eval("(1..-2).step(10)")].should == [1]
      @array[eval("(1...-2).step(10)")].should == [1]

      # start with negative index, end with positive index
      @array[eval("(-4..4).step(1)")].should == [2, 3, 4]
      @array[eval("(-4...4).step(1)")].should == [2, 3]

      @array[eval("(-4..4).step(2)")].should == [2, 4]
      @array[eval("(-4...4).step(2)")].should == [2]

      @array[eval("(-4..4).step(10)")].should == [2]
      @array[eval("(-4...4).step(10)")].should == [2]

      # start with negative index, end with negative index
      @array[eval("(-4..-2).step(1)")].should == [2, 3, 4]
      @array[eval("(-4...-2).step(1)")].should == [2, 3]

      @array[eval("(-4..-2).step(2)")].should == [2, 4]
      @array[eval("(-4...-2).step(2)")].should == [2]

      @array[eval("(-4..-2).step(10)")].should == [2]
      @array[eval("(-4...-2).step(10)")].should == [2]
    end

    it "has closed range and negative steps" do
      # start and end with 0
      @array[eval("(0..0).step(-1)")].should == [0]
      @array[eval("(0...0).step(-1)")].should == []

      @array[eval("(0..0).step(-2)")].should == [0]
      @array[eval("(0...0).step(-2)")].should == []

      @array[eval("(0..0).step(-10)")].should == [0]
      @array[eval("(0...0).step(-10)")].should == []

      # start and end with positive index
      @array[eval("(1..3).step(-1)")].should == []
      @array[eval("(1...3).step(-1)")].should == []

      @array[eval("(1..3).step(-2)")].should == []
      @array[eval("(1...3).step(-2)")].should == []

      @array[eval("(1..3).step(-10)")].should == []
      @array[eval("(1...3).step(-10)")].should == []

      # start with positive index, end with negative index
      @array[eval("(1..-2).step(-1)")].should == []
      @array[eval("(1...-2).step(-1)")].should == []

      @array[eval("(1..-2).step(-2)")].should ==  []
      @array[eval("(1...-2).step(-2)")].should ==  []

      @array[eval("(1..-2).step(-10)")].should == []
      @array[eval("(1...-2).step(-10)")].should == []

      # start with negative index, end with positive index
      @array[eval("(-4..4).step(-1)")].should == []
      @array[eval("(-4...4).step(-1)")].should == []

      @array[eval("(-4..4).step(-2)")].should == []
      @array[eval("(-4...4).step(-2)")].should == []

      @array[eval("(-4..4).step(-10)")].should == []
      @array[eval("(-4...4).step(-10)")].should == []

      # start with negative index, end with negative index
      @array[eval("(-4..-2).step(-1)")].should == []
      @array[eval("(-4...-2).step(-1)")].should == []

      @array[eval("(-4..-2).step(-2)")].should == []
      @array[eval("(-4...-2).step(-2)")].should == []

      @array[eval("(-4..-2).step(-10)")].should == []
      @array[eval("(-4...-2).step(-10)")].should == []
    end

    it "has inverted closed range and positive steps" do
      # start and end with positive index
      @array[eval("(3..1).step(1)")].should == []
      @array[eval("(3...1).step(1)")].should == []

      @array[eval("(3..1).step(2)")].should == []
      @array[eval("(3...1).step(2)")].should == []

      @array[eval("(3..1).step(10)")].should == []
      @array[eval("(3...1).step(10)")].should == []

      # start with negative index, end with positive index
      @array[eval("(-2..1).step(1)")].should == []
      @array[eval("(-2...1).step(1)")].should == []

      @array[eval("(-2..1).step(2)")].should ==  []
      @array[eval("(-2...1).step(2)")].should ==  []

      @array[eval("(-2..1).step(10)")].should == []
      @array[eval("(-2...1).step(10)")].should == []

      # start with positive index, end with negative index
      @array[eval("(4..-4).step(1)")].should == []
      @array[eval("(4...-4).step(1)")].should == []

      @array[eval("(4..-4).step(2)")].should == []
      @array[eval("(4...-4).step(2)")].should == []

      @array[eval("(4..-4).step(10)")].should == []
      @array[eval("(4...-4).step(10)")].should == []

      # start with negative index, end with negative index
      @array[eval("(-2..-4).step(1)")].should == []
      @array[eval("(-2...-4).step(1)")].should == []

      @array[eval("(-2..-4).step(2)")].should == []
      @array[eval("(-2...-4).step(2)")].should == []

      @array[eval("(-2..-4).step(10)")].should == []
      @array[eval("(-2...-4).step(10)")].should == []
    end

    it "has range with bounds outside of array" do
      # end is equal to array's length
      @array[(0..6).step(1)].should == [0, 1, 2, 3, 4, 5]
      -> { @array[(0..6).step(2)] }.should.raise(RangeError)

      # end is greater than length with positive steps
      @array[(1..6).step(2)].should == [1, 3, 5]
      @array[(2..7).step(2)].should == [2, 4]
      -> { @array[(2..8).step(2)] }.should.raise(RangeError)

      # begin is greater than length with negative steps
      @array[(6..1).step(-2)].should == [5, 3, 1]
      @array[(7..2).step(-2)].should == [5, 3]
      -> { @array[(8..2).step(-2)] }.should.raise(RangeError)
    end

    it "has endless range with start outside of array's bounds" do
      @array[eval("(6..).step(1)")].should == []
      @array[eval("(7..).step(1)")].should == nil

      @array[eval("(6..).step(2)")].should == []
      -> { @array[eval("(7..).step(2)")] }.should.raise(RangeError)
    end
  end

  it "can accept beginless ranges" do
    a = [0, 1, 2, 3, 4, 5]
    a[(..3)].should == [0, 1, 2, 3]
    a[(...3)].should == [0, 1, 2]
    a[(..-3)].should == [0, 1, 2, 3]
    a[(...-3)].should == [0, 1, 2]
    a[(..0)].should == [0]
    a[(...0)].should == []
    a[(..9)].should == [0, 1, 2, 3, 4, 5]
    a[(...9)].should == [0, 1, 2, 3, 4, 5]
    a[(..-9)].should == []
    a[(...-9)].should == []
  end

  describe "can be sliced with Enumerator::ArithmeticSequence" do
    it "with infinite/inverted ranges and negative steps" do
      array = [0, 1, 2, 3, 4, 5]
      array[(2..).step(-1)].should == [2, 1, 0]
      array[(2..).step(-2)].should == [2, 0]
      array[(2..).step(-3)].should == [2]
      array[(2..).step(-4)].should == [2]

      array[(-3..).step(-1)].should == [3, 2, 1, 0]
      array[(-3..).step(-2)].should == [3, 1]
      array[(-3..).step(-3)].should == [3, 0]
      array[(-3..).step(-4)].should == [3]
      array[(-3..).step(-5)].should == [3]

      array[(..0).step(-1)].should == [5, 4, 3, 2, 1, 0]
      array[(..0).step(-2)].should == [5, 3, 1]
      array[(..0).step(-3)].should == [5, 2]
      array[(..0).step(-4)].should == [5, 1]
      array[(..0).step(-5)].should == [5, 0]
      array[(..0).step(-6)].should == [5]
      array[(..0).step(-7)].should == [5]

      array[(...0).step(-1)].should == [5, 4, 3, 2, 1]
      array[(...0).step(-2)].should == [5, 3, 1]
      array[(...0).step(-3)].should == [5, 2]
      array[(...0).step(-4)].should == [5, 1]
      array[(...0).step(-5)].should == [5]
      array[(...0).step(-6)].should == [5]

      array[(...1).step(-1)].should == [5, 4, 3, 2]
      array[(...1).step(-2)].should == [5, 3]
      array[(...1).step(-3)].should == [5, 2]
      array[(...1).step(-4)].should == [5]
      array[(...1).step(-5)].should == [5]

      array[(..-5).step(-1)].should == [5, 4, 3, 2, 1]
      array[(..-5).step(-2)].should == [5, 3, 1]
      array[(..-5).step(-3)].should == [5, 2]
      array[(..-5).step(-4)].should == [5, 1]
      array[(..-5).step(-5)].should == [5]
      array[(..-5).step(-6)].should == [5]

      array[(...-5).step(-1)].should == [5, 4, 3, 2]
      array[(...-5).step(-2)].should == [5, 3]
      array[(...-5).step(-3)].should == [5, 2]
      array[(...-5).step(-4)].should == [5]
      array[(...-5).step(-5)].should == [5]

      array[(4..1).step(-1)].should == [4, 3, 2, 1]
      array[(4..1).step(-2)].should == [4, 2]
      array[(4..1).step(-3)].should == [4, 1]
      array[(4..1).step(-4)].should == [4]
      array[(4..1).step(-5)].should == [4]

      array[(4...1).step(-1)].should == [4, 3, 2]
      array[(4...1).step(-2)].should == [4, 2]
      array[(4...1).step(-3)].should == [4]
      array[(4...1).step(-4)].should == [4]

      array[(-2..1).step(-1)].should == [4, 3, 2, 1]
      array[(-2..1).step(-2)].should == [4, 2]
      array[(-2..1).step(-3)].should == [4, 1]
      array[(-2..1).step(-4)].should == [4]
      array[(-2..1).step(-5)].should == [4]

      array[(-2...1).step(-1)].should == [4, 3, 2]
      array[(-2...1).step(-2)].should == [4, 2]
      array[(-2...1).step(-3)].should == [4]
      array[(-2...1).step(-4)].should == [4]

      array[(4..-5).step(-1)].should == [4, 3, 2, 1]
      array[(4..-5).step(-2)].should == [4, 2]
      array[(4..-5).step(-3)].should == [4, 1]
      array[(4..-5).step(-4)].should == [4]
      array[(4..-5).step(-5)].should == [4]

      array[(4...-5).step(-1)].should == [4, 3, 2]
      array[(4...-5).step(-2)].should == [4, 2]
      array[(4...-5).step(-3)].should == [4]
      array[(4...-5).step(-4)].should == [4]

      array[(-2..-5).step(-1)].should == [4, 3, 2, 1]
      array[(-2..-5).step(-2)].should == [4, 2]
      array[(-2..-5).step(-3)].should == [4, 1]
      array[(-2..-5).step(-4)].should == [4]
      array[(-2..-5).step(-5)].should == [4]

      array[(-2...-5).step(-1)].should == [4, 3, 2]
      array[(-2...-5).step(-2)].should == [4, 2]
      array[(-2...-5).step(-3)].should == [4]
      array[(-2...-5).step(-4)].should == [4]
    end
  end

  it "can accept nil...nil ranges" do
    a = [0, 1, 2, 3, 4, 5]
    a[eval("(nil...nil)")].should == a
    a[(...nil)].should == a
    a[eval("(nil..)")].should == a
  end
end

describe "Array.[]" do
  it "[] should return a new array populated with the given elements" do
    array = Array[1, 'a', nil]
    array[0].should == 1
    array[1].should == 'a'
    array[2].should == nil
  end

  it "when applied to a literal nested array, unpacks its elements into the containing array" do
    Array[1, 2, *[3, 4, 5]].should == [1, 2, 3, 4, 5]
  end

  it "when applied to a nested referenced array, unpacks its elements into the containing array" do
    splatted_array = Array[3, 4, 5]
    Array[1, 2, *splatted_array].should == [1, 2, 3, 4, 5]
  end

  it "can unpack 2 or more nested referenced array" do
    splatted_array = Array[3, 4, 5]
    splatted_array2 = Array[6, 7, 8]
    Array[1, 2, *splatted_array, *splatted_array2].should == [1, 2, 3, 4, 5, 6, 7, 8]
  end

  it "constructs a nested Hash for tailing key-value pairs" do
    Array[1, 2, 3 => 4, 5 => 6].should == [1, 2, { 3 => 4, 5 => 6 }]
  end

  describe "with a subclass of Array" do
    before :each do
      ScratchPad.clear
    end

    it "returns an instance of the subclass" do
      ArraySpecs::MyArray[1, 2, 3].should.instance_of?(ArraySpecs::MyArray)
    end

    it "does not call #initialize on the subclass instance" do
      ArraySpecs::MyArray[1, 2, 3].should == [1, 2, 3]
      ScratchPad.recorded.should == nil
    end
  end
end
