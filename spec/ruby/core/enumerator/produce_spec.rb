require_relative '../../spec_helper'

describe "Enumerator.produce" do
  it "creates an infinite enumerator" do
    enum = Enumerator.produce(0) { |prev| prev + 1 }
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
end
