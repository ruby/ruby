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
        @array.fetch_values(-1).should == [:c]
      end

      it "returns the values for indexes ordered in the order of the requested indexes" do
        @array.fetch_values(2, 0).should == [:c, :a]
      end
    end

    describe "with unmatched indexes" do
      it "raises a index error if no block is provided" do
        -> { @array.fetch_values(0, 1, 44) }.should raise_error(IndexError, "index 44 outside of array bounds: -3...3")
      end

      it "returns the default value from block" do
        @array.fetch_values(44) { |index| "`#{index}' is not found" }.should == ["`44' is not found"]
        @array.fetch_values(0, 44) { |index| "`#{index}' is not found" }.should == [:a, "`44' is not found"]
      end
    end

    describe "without keys" do
      it "returns an empty Array" do
        @array.fetch_values.should == []
      end
    end

    it "tries to convert the passed argument to an Integer using #to_int" do
      obj = mock('to_int')
      obj.should_receive(:to_int).and_return(2)
      @array.fetch_values(obj).should == [:c]
    end

    it "does not support a Range object as argument" do
      -> {
        @array.fetch_values(1..2)
      }.should raise_error(TypeError, "no implicit conversion of Range into Integer")
    end

    it "raises a TypeError when the passed argument can't be coerced to Integer" do
      -> { [].fetch_values("cat") }.should raise_error(TypeError, "no implicit conversion of String into Integer")
    end
  end
end
