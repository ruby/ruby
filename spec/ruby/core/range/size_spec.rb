require_relative '../../spec_helper'

describe "Range#size" do
  it "returns the number of elements in the range" do
    (1..16).size.should == 16
    (1...16).size.should == 15
  end

  it "returns 0 if last is less than first" do
    (16..0).size.should == 0
  end

  it 'returns Float::INFINITY for increasing, infinite ranges' do
    (0..Float::INFINITY).size.should == Float::INFINITY
  end

  it 'returns Float::INFINITY for endless ranges if the start is numeric' do
    eval("(1..)").size.should == Float::INFINITY
  end

  it 'returns nil for endless ranges if the start is not numeric' do
    eval("('z'..)").size.should == nil
  end

  ruby_version_is ""..."3.4" do
    it 'returns Float::INFINITY for all beginless ranges if the end is numeric' do
      (..1).size.should == Float::INFINITY
      (...0.5).size.should == Float::INFINITY
    end

    it 'returns nil for all beginless ranges if the end is not numeric' do
      (...'o').size.should == nil
    end

    it 'returns nil if the start and the end is both nil' do
      (nil..nil).size.should == nil
    end
  end

  ruby_version_is ""..."3.4" do
    it "returns the number of elements in the range" do
      (1.0..16.0).size.should == 16
      (1.0...16.0).size.should == 15
      (1.0..15.9).size.should == 15
      (1.1..16.0).size.should == 15
      (1.1..15.9).size.should == 15
    end

    it "returns 0 if last is less than first" do
      (16.0..0.0).size.should == 0
      (Float::INFINITY..0).size.should == 0
    end

    it 'returns Float::INFINITY for increasing, infinite ranges' do
      (-Float::INFINITY..0).size.should == Float::INFINITY
      (-Float::INFINITY..Float::INFINITY).size.should == Float::INFINITY
    end

    it 'returns Float::INFINITY for endless ranges if the start is numeric' do
      eval("(0.5...)").size.should == Float::INFINITY
    end

    it 'returns nil for endless ranges if the start is not numeric' do
      eval("([]...)").size.should == nil
    end
  end

  ruby_version_is "3.4" do
    it 'raises TypeError if a range is not iterable' do
      -> { (1.0..16.0).size }.should raise_error(TypeError, /can't iterate from/)
      -> { (1.0...16.0).size }.should raise_error(TypeError, /can't iterate from/)
      -> { (1.0..15.9).size }.should raise_error(TypeError, /can't iterate from/)
      -> { (1.1..16.0).size }.should raise_error(TypeError, /can't iterate from/)
      -> { (1.1..15.9).size }.should raise_error(TypeError, /can't iterate from/)
      -> { (16.0..0.0).size }.should raise_error(TypeError, /can't iterate from/)
      -> { (Float::INFINITY..0).size }.should raise_error(TypeError, /can't iterate from/)
      -> { (-Float::INFINITY..0).size }.should raise_error(TypeError, /can't iterate from/)
      -> { (-Float::INFINITY..Float::INFINITY).size }.should raise_error(TypeError, /can't iterate from/)
      -> { (..1).size }.should raise_error(TypeError, /can't iterate from/)
      -> { (...0.5).size }.should raise_error(TypeError, /can't iterate from/)
      -> { (..nil).size }.should raise_error(TypeError, /can't iterate from/)
      -> { (...'o').size }.should raise_error(TypeError, /can't iterate from/)
      -> { eval("(0.5...)").size }.should raise_error(TypeError, /can't iterate from/)
      -> { eval("([]...)").size }.should raise_error(TypeError, /can't iterate from/)
    end
  end

  it "returns nil if first and last are not Numeric" do
    (:a..:z).size.should be_nil
    ('a'..'z').size.should be_nil
  end
end
