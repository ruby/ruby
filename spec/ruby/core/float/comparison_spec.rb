require_relative '../../spec_helper'

describe "Float#<=>" do
  it "returns -1, 0, 1 when self is less than, equal, or greater than other" do
    (1.5 <=> 5).should == -1
    (2.45 <=> 2.45).should == 0
    ((bignum_value*1.1) <=> bignum_value).should == 1
  end

  it "returns nil if one side is NaN" do
    [1.0, 42, bignum_value].each { |n|
      (nan_value <=> n).should == nil
      (n <=> nan_value).should == nil
    }
  end

  it "handles positive infinity" do
    [1.0, 42, bignum_value].each { |n|
      (infinity_value <=> n).should == 1
      (n <=> infinity_value).should == -1
    }
  end

  it "handles negative infinity" do
    [1.0, 42, bignum_value].each { |n|
      (-infinity_value <=> n).should == -1
      (n <=> -infinity_value).should == 1
    }
  end

  it "returns nil when the given argument is not a Float" do
    (1.0 <=> "1").should be_nil
    (1.0 <=> "1".freeze).should be_nil
    (1.0 <=> :one).should be_nil
    (1.0 <=> true).should be_nil
  end

  it "compares using #coerce when argument is not a Float" do
    klass = Class.new do
      attr_reader :call_count
      def coerce(other)
        @call_count ||= 0
        @call_count += 1
        [other, 42.0]
      end
    end

    coercible = klass.new
    (2.33 <=> coercible).should == -1
    (42.0 <=> coercible).should == 0
    (43.0 <=> coercible).should == 1
    coercible.call_count.should == 3
  end

  it "raises TypeError when #coerce misbehaves" do
    klass = Class.new do
      def coerce(other)
        :incorrect
      end
    end

    bad_coercible = klass.new
    -> {
      4.2 <=> bad_coercible
    }.should raise_error(TypeError, "coerce must return [x, y]")
  end

  it "returns the correct result when one side is infinite" do
    (infinity_value <=> Float::MAX.to_i*2).should == 1
    (-Float::MAX.to_i*2 <=> infinity_value).should == -1
    (-infinity_value <=> -Float::MAX.to_i*2).should == -1
    (-Float::MAX.to_i*2 <=> -infinity_value).should == 1
  end

  it "returns 0 when self is Infinity and other is infinite?=1" do
    obj = Object.new
    def obj.infinite?
      1
    end
    (infinity_value <=> obj).should == 0
  end

  it "returns 1 when self is Infinity and other is infinite?=-1" do
    obj = Object.new
    def obj.infinite?
      -1
    end
    (infinity_value <=> obj).should == 1
  end

  it "returns 1 when self is Infinity and other is infinite?=nil (which means finite)" do
    obj = Object.new
    def obj.infinite?
      nil
    end
    (infinity_value <=> obj).should == 1
  end

  it "returns 0 for -0.0 and 0.0" do
    (-0.0 <=> 0.0).should == 0
    (0.0 <=> -0.0).should == 0
  end

  it "returns 0 for -0.0 and 0" do
    (-0.0 <=> 0).should == 0
    (0 <=> -0.0).should == 0
  end

  it "returns 0 for 0.0 and 0" do
    (0.0 <=> 0).should == 0
    (0 <=> 0.0).should == 0
  end
end
