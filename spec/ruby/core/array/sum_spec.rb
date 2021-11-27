require_relative '../../spec_helper'

describe "Array#sum" do
  it "returns the sum of elements" do
    [1, 2, 3].sum.should == 6
  end

  it "applies a block to each element before adding if it's given" do
    [1, 2, 3].sum { |i| i * 10 }.should == 60
  end

  # https://bugs.ruby-lang.org/issues/12217
  # https://github.com/ruby/ruby/blob/master/doc/ChangeLog-2.4.0#L6208-L6214
  it "uses Kahan's compensated summation algorithm for precise sum of float numbers" do
    floats = [2.7800000000000002, 5.0, 2.5, 4.44, 3.89, 3.89, 4.44, 7.78, 5.0, 2.7800000000000002, 5.0, 2.5]
    naive_sum = floats.reduce { |sum, e| sum + e }
    naive_sum.should == 50.00000000000001
    floats.sum.should == 50.0
  end

  it "handles infinite values and NaN" do
    [1.0, Float::INFINITY].sum.should == Float::INFINITY
    [1.0, -Float::INFINITY].sum.should == -Float::INFINITY
    [1.0, Float::NAN].sum.should.nan?

    [Float::INFINITY, 1.0].sum.should == Float::INFINITY
    [-Float::INFINITY, 1.0].sum.should == -Float::INFINITY
    [Float::NAN, 1.0].sum.should.nan?

    [Float::NAN, Float::INFINITY].sum.should.nan?
    [Float::INFINITY, Float::NAN].sum.should.nan?

    [Float::INFINITY, -Float::INFINITY].sum.should.nan?
    [-Float::INFINITY, Float::INFINITY].sum.should.nan?

    [Float::INFINITY, Float::INFINITY].sum.should == Float::INFINITY
    [-Float::INFINITY, -Float::INFINITY].sum.should == -Float::INFINITY
    [Float::NAN, Float::NAN].sum.should.nan?
  end

  it "returns init value if array is empty" do
    [].sum(-1).should == -1
  end

  it "returns 0 if array is empty and init is omitted" do
    [].sum.should == 0
  end

  it "adds init value to the sum of elements" do
    [1, 2, 3].sum(10).should == 16
  end

  it "can be used for non-numeric objects by providing init value" do
    ["a", "b", "c"].sum("").should == "abc"
  end

  it 'raises TypeError if any element are not numeric' do
    -> { ["a"].sum }.should raise_error(TypeError)
  end

  it 'raises TypeError if any element cannot be added to init value' do
    -> { [1].sum([]) }.should raise_error(TypeError)
  end

  it "calls + to sum the elements" do
    a = mock("a")
    b = mock("b")
    a.should_receive(:+).with(b).and_return(42)
    [b].sum(a).should == 42
  end
end
