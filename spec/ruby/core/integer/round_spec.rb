require_relative '../../spec_helper'
require_relative 'shared/to_i'
require_relative 'shared/integer_rounding'

describe "Integer#round" do
  it_behaves_like :integer_to_i, :round
  it_behaves_like :integer_rounding_positive_precision, :round

  # redmine:5228
  it "returns itself rounded if passed a negative value" do
    +249.round(-2).should eql(+200)
    -249.round(-2).should eql(-200)
    (+25 * 10**70 - 1).round(-71).should eql(+20 * 10**70)
    (-25 * 10**70 + 1).round(-71).should eql(-20 * 10**70)
  end

  it "returns itself rounded to nearest if passed a negative value" do
    +250.round(-2).should eql(+300)
    -250.round(-2).should eql(-300)
    (+25 * 10**70).round(-71).should eql(+30 * 10**70)
    (-25 * 10**70).round(-71).should eql(-30 * 10**70)
  end

  platform_is_not wordsize: 32 do
    it "raises a RangeError when passed a big negative value" do
      -> { 42.round(fixnum_min) }.should raise_error(RangeError)
    end
  end

  it "raises a RangeError when passed Float::INFINITY" do
    -> { 42.round(Float::INFINITY) }.should raise_error(RangeError)
  end

  it "raises a RangeError when passed a beyond signed int" do
    -> { 42.round(1<<31) }.should raise_error(RangeError)
  end

  it "raises a TypeError when passed a String" do
    -> { 42.round("4") }.should raise_error(TypeError)
  end

  it "raises a TypeError when its argument cannot be converted to an Integer" do
    -> { 42.round(nil) }.should raise_error(TypeError)
  end

  it "calls #to_int on the argument to convert it to an Integer" do
    obj = mock("Object")
    obj.should_receive(:to_int).and_return(0)
    42.round(obj)
  end

  it "raises a TypeError when #to_int does not return an Integer" do
    obj = mock("Object")
    obj.stub!(:to_int).and_return([])
    -> { 42.round(obj) }.should raise_error(TypeError)
  end

  it "returns different rounded values depending on the half option" do
    25.round(-1, half: :up).should      eql(30)
    25.round(-1, half: :down).should    eql(20)
    25.round(-1, half: :even).should    eql(20)
    25.round(-1, half: nil).should      eql(30)
    35.round(-1, half: :up).should      eql(40)
    35.round(-1, half: :down).should    eql(30)
    35.round(-1, half: :even).should    eql(40)
    35.round(-1, half: nil).should      eql(40)
    (-25).round(-1, half: :up).should   eql(-30)
    (-25).round(-1, half: :down).should eql(-20)
    (-25).round(-1, half: :even).should eql(-20)
    (-25).round(-1, half: nil).should   eql(-30)
  end

  it "returns itself if passed a positive precision and the half option" do
    35.round(1, half: :up).should      eql(35)
    35.round(1, half: :down).should    eql(35)
    35.round(1, half: :even).should    eql(35)
  end

  it "raises ArgumentError for an unknown rounding mode" do
    -> { 42.round(-1, half: :foo) }.should raise_error(ArgumentError, /invalid rounding mode: foo/)
    -> { 42.round(1, half: :foo) }.should raise_error(ArgumentError, /invalid rounding mode: foo/)
  end
end
