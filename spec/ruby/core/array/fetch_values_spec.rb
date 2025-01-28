require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Array#fetch_values" do
  before :each do
    @array = [:a, :b, :c]
  end

  ruby_version_is "3.4" do
    describe "with matched indexes" do
      it "returns the values for indexes" do
        @array.fetch_values(0).should == [:a]
        @array.fetch_values(0, 2).should == [:a, :c]
      end

      it "returns the values for indexes ordered in the order of the requested indexes" do
        @array.fetch_values(2, 0).should == [:c, :a]
      end
    end

    describe "with unmatched indexes" do
      it "raises a index error if no block is provided" do
        -> { @array.fetch_values(0, 1, 44) }.should raise_error(IndexError)
      end

      it "returns the default value from block" do
        @array.fetch_values(44) { |index| "`#{index}` not found" }.should == ["`44` not found"]
        @array.fetch_values(0, 44) { |index| "`#{index}` not found" }.should == [:a, "`44` not found"]
      end
    end

    describe "without keys" do
      it "returns an empty Array" do
        @array.fetch_values.should == []
      end
    end

    describe "with ranges" do
      it "returns an array of elements in the ranges" do
        @array.fetch_values(0..2, 1...3, 2..-2).should == [:a, :b, :c, :b, :c]
      end

      it "returns an empty array if the range is empty" do
        @array.fetch_values(6..4).should == []
      end

      it "handles negative ranges" do
        @array.fetch_values(-2..-1).should == [:b, :c]
      end

      it "raises if the range is out of bounds" do
        -> { @array.fetch_values(10..20) }.should raise_error(IndexError)
      end

      it "calls the block if the range is out of bounds" do
        @array.fetch_values(5..7) { |i| "`#{i}` not found" }.should == ["`5` not found", "`6` not found", "`7` not found"]
      end
    end

    describe "I don't know what to do" do
      it "negative range is out of bounds" do
        @array.fetch_values(-7..-5) { |i| "`#{i}` not found" }.should == ??
      end

      it "out of bounds endless ranges" do
        [].fetch_values(10..).should == ??
      end

      it "out of bounds beginless ranges" do
        [].fetch_values(..10).should == ??
      end

      it "out of bounds negative endless ranges" do
        [].fetch_values(-10..).should == ??
      end

      it "out of bounds negatie beginless ranges" do
        [].fetch_values(..-10).should == ??
      end
    end

    it "tries to convert the passed argument to an Integer using #to_int" do
      obj = mock('to_int')
      obj.should_receive(:to_int).and_return(2)
      @array.fetch_values(obj).should == [:c]
    end

    it "raises a TypeError when the passed argument can't be coerced to Integer" do
      -> { [].fetch_values("cat") }.should raise_error(TypeError)
    end
  end
end
