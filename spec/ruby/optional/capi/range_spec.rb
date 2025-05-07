require_relative 'spec_helper'

load_extension("range")

describe "C-API Range function" do
  before :each do
    @s = CApiRangeSpecs.new
  end

  describe "rb_range_new" do
    it "constructs a range using the given start and end" do
      range = @s.rb_range_new('a', 'c')
      range.should == ('a'..'c')

      range.first.should == 'a'
      range.last.should == 'c'
    end

    it "includes the end object when the third parameter is omitted or false" do
      @s.rb_range_new('a', 'c').to_a.should == ['a', 'b', 'c']
      @s.rb_range_new(1, 3).to_a.should == [1, 2, 3]

      @s.rb_range_new('a', 'c', false).to_a.should == ['a', 'b', 'c']
      @s.rb_range_new(1, 3, false).to_a.should == [1, 2, 3]

      @s.rb_range_new('a', 'c', true).to_a.should == ['a', 'b']
      @s.rb_range_new(1, 3, 1).to_a.should == [1, 2]

      @s.rb_range_new(1, 3, mock('[1,2]')).to_a.should == [1, 2]
      @s.rb_range_new(1, 3, :test).to_a.should == [1, 2]
    end

    it "raises an ArgumentError when the given start and end can't be compared by using #<=>" do
      -> { @s.rb_range_new(1, mock('x'))         }.should raise_error(ArgumentError)
      -> { @s.rb_range_new(mock('x'), mock('y')) }.should raise_error(ArgumentError)
    end
  end

  describe "rb_range_values" do
    it "stores the range properties" do
      beg, fin, excl = @s.rb_range_values(10..20)
      beg.should == 10
      fin.should == 20
      excl.should be_false
    end

    it "stores the range properties of non-Range object" do
      range_like = mock('range')

      def range_like.begin
        10
      end

      def range_like.end
        20
      end

      def range_like.exclude_end?
        false
      end

      beg, fin, excl = @s.rb_range_values(range_like)
      beg.should == 10
      fin.should == 20
      excl.should be_false
    end
  end

  describe "rb_range_beg_len" do
    it "returns correct begin, length and result" do
      r = 2..5
      begp, lenp, result = @s.rb_range_beg_len(r, 0, 0, 10, 0)
      result.should be_true
      begp.should == 2
      lenp.should == 4
    end

    it "returns nil when not in range" do
      r = 2..5
      begp, lenp, result = @s.rb_range_beg_len(r, 0, 0, 1, 0)
      result.should be_nil
    end

    it "raises a RangeError when not in range and err is 1" do
      r = -5..-1
      -> { @s.rb_range_beg_len(r, 0, 0, 1, 1) }.should raise_error(RangeError)
    end

    it "returns nil when not in range and err is 0" do
      r = -5..-1
      begp, lenp, result =  @s.rb_range_beg_len(r, 0, 0, 1, 0)
      result.should be_nil
    end
  end

  describe "rb_arithmetic_sequence_extract" do
    it "returns begin, end, step, exclude end of an instance of an Enumerator::ArithmeticSequence" do
      enum = (10..20).step(5)
      enum.should.kind_of?(Enumerator::ArithmeticSequence)

      @s.rb_arithmetic_sequence_extract(enum).should == [1, 10, 20, 5, false]
    end

    it "returns begin, end, step, exclude end of an instance of a Range" do
      range = (10..20)
      @s.rb_arithmetic_sequence_extract(range).should == [1, 10, 20, 1, false]
    end

    it "returns begin, end, step, exclude end of a non-Range object with Range properties" do
      object = Object.new
      def object.begin
        10
      end
      def object.end
        20
      end
      def object.exclude_end?
        false
      end

      @s.rb_arithmetic_sequence_extract(object).should == [1, 10, 20, 1, false]
    end

    it "returns failed status if given object is not Enumerator::ArithmeticSequence or Range or Range-like object" do
      object = Object.new
      @s.rb_arithmetic_sequence_extract(object).should == [0]
    end
  end

  describe "rb_arithmetic_sequence_beg_len_step" do
    it "returns correct begin, length, step and result" do
      as = (2..5).step(5)
      error_code = 0

      success, beg, len, step = @s.rb_arithmetic_sequence_beg_len_step(as, 6, error_code)
      success.should be_true

      beg.should == 2
      len.should == 4
      step.should == 5
    end

    it "takes into account excluded end boundary" do
      as = (2...5).step(1)
      error_code = 0

      success, _, len, _ = @s.rb_arithmetic_sequence_beg_len_step(as, 6, error_code)
      success.should be_true
      len.should == 3
    end

    it "adds length to negative begin boundary" do
      as = (-2..5).step(1)
      error_code = 0

      success, beg, len, _ = @s.rb_arithmetic_sequence_beg_len_step(as, 6, error_code)
      success.should be_true

      beg.should == 4
      len.should == 2
    end

    it "adds length to negative end boundary" do
      as = (2..-1).step(1)
      error_code = 0

      success, beg, len, _ = @s.rb_arithmetic_sequence_beg_len_step(as, 6, error_code)
      success.should be_true

      beg.should == 2
      len.should == 4
    end

    it "truncates arithmetic sequence length if end boundary greater than specified length value" do
      as = (2..10).step(1)
      error_code = 0

      success, _, len, _ = @s.rb_arithmetic_sequence_beg_len_step(as, 6, error_code)
      success.should be_true
      len.should == 4
    end

    it "returns inverted begin and end boundaries when step is negative" do
      as = (2..5).step(-2)
      error_code = 0

      success, beg, len, step = @s.rb_arithmetic_sequence_beg_len_step(as, 6, error_code)
      success.should be_true

      beg.should == 5
      len.should == 0
      step.should == -2
    end

    it "returns nil when not in range and error code = 0" do
      as = (2..5).step(1)
      error_code = 0

      success, = @s.rb_arithmetic_sequence_beg_len_step(as, 1, error_code)
      success.should be_nil
    end

    it "returns nil when not in range, negative boundaries and error code = 0" do
      as = (-5..-1).step(1)
      error_code = 0

      success, = @s.rb_arithmetic_sequence_beg_len_step(as, 1, 0)
      success.should be_nil
    end

    it "returns begin, length and step and doesn't raise a RangeError when not in range and error code = 1" do
      as = (2..5).step(1)
      error_code = 1

      success, beg, len, step = @s.rb_arithmetic_sequence_beg_len_step(as, 1, error_code)
      success.should be_true

      beg.should == 2
      len.should == 4
      step.should == 1
    end

    it "returns nil and doesn't raise a RangeError when not in range, negative boundaries and error code = 1" do
      as = (-5..-1).step(1)
      error_code = 1

      success, = @s.rb_arithmetic_sequence_beg_len_step(as, 1, error_code)
      success.should be_nil
    end
  end
end
