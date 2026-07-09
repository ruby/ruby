require_relative '../../spec_helper'

describe "Enumerator.produce" do
  it "creates an infinite enumerator" do
    enum = Enumerator.produce(0) { |prev| prev + 1 }

    enum.size.should == Float::INFINITY
    enum.take(5).should == [0, 1, 2, 3, 4]
  end

  it "terminates iteration when block raises StopIteration exception" do
    enum = Enumerator.produce(0) do | prev|
      raise StopIteration if prev >= 2
      prev + 1
    end

    enum.to_a.should == [0, 1, 2]
  end

  context "when initial value skipped" do
    it "uses nil instead" do
      ScratchPad.record []
      enum = Enumerator.produce { |prev| ScratchPad << prev; (prev || 0) + 1 }

      enum.take(3).should == [1, 2, 3]
      ScratchPad.recorded.should == [nil, 1, 2]
    end

    it "starts enumerable from result of first block call" do
      array = "a\nb\nc\nd".lines
      lines = Enumerator.produce { array.shift }.take_while { |s| s }

      lines.should == ["a\n", "b\n", "c\n", "d"]
    end
  end

  it "raises ArgumentError when no block is given" do
    -> { Enumerator.produce }.should.raise(ArgumentError, "no block given")
  end

  ruby_version_is ""..."4.0" do
    it "accepts keyword arguments as the initial value" do
      enum = Enumerator.produce(a: 1, b: 1) {}
      enum.take(1).should == [{a: 1, b: 1}]
    end
  end

  ruby_version_is "4.0" do
    it "raises ArgumentError for unknown keyword arguments" do
      -> { Enumerator.produce(a: 1, b: 1) {} }.should.raise(ArgumentError, /unknown keywords/)
    end
  end

  ruby_version_is "4.0" do
    context "with size keyword argument" do
      it "sets the size of the enumerator" do
        enum = Enumerator.produce(0, size: 10) { |n| n + 1 }

        enum.size.should == 10
        enum.take(5).should == [0, 1, 2, 3, 4]
      end

      it "accepts a callable" do
        enum = Enumerator.produce(0, size: -> { 5 * 5 }) { |n| n + 1 }

        enum.size.should == 25
        enum.take(5).should == [0, 1, 2, 3, 4]
      end

      it "accepts nil" do
        enum = Enumerator.produce(0, size: nil) { |n| n + 1 }

        enum.size.should == nil
        enum.take(5).should == [0, 1, 2, 3, 4]
      end
    end
  end
end
