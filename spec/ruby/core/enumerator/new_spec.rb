require_relative '../../spec_helper'

describe "Enumerator.new" do
  context "no block given" do
    it "raises" do
      -> { Enumerator.new(1, :upto, 3) }.should.raise(ArgumentError)
    end
  end

  context "when passed a block" do
    it "defines iteration with block, yielder argument and calling << method" do
      enum = Enumerator.new do |yielder|
        a = 1

        loop do
          yielder << a
          a = a + 1
        end
      end

      enum.take(3).should == [1, 2, 3]
    end

    it "defines iteration with block, yielder argument and calling yield method" do
      enum = Enumerator.new do |yielder|
        a = 1

        loop do
          yielder.yield(a)
          a = a + 1
        end
      end

      enum.take(3).should == [1, 2, 3]
    end

    it "defines iteration with block, yielder argument and treating it as a proc" do
      enum = Enumerator.new do |yielder|
        "a\nb\nc".each_line(&yielder)
      end

      enum.to_a.should == ["a\n", "b\n", "c"]
    end

    describe '#yield' do
      it 'accepts a single argument' do
        Enumerator.new { |y| y.yield(1) }.to_a.should == [1]
        Enumerator.new { |y| y.yield(1) }.first.should == 1
      end

      it 'accepts multiple arguments' do
        Enumerator.new { |y| y.yield(1, 2) }.to_a.should == [[1, 2]]
        Enumerator.new { |y| y.yield(1, 2) }.first.should == [1, 2]
      end

      it "doesn't double-wrap arrays" do
        Enumerator.new { |y| y.yield([1]) }.to_a.should == [[1]]
        Enumerator.new { |y| y.yield([1]) }.first.should == [1]

        Enumerator.new { |y| y.yield([1, 2]) }.to_a.should == [[1, 2]]
        Enumerator.new { |y| y.yield([1, 2]) }.first.should == [1, 2]
      end

      it 'returns nil' do
        ScratchPad.record []
        Enumerator.new do |y|
          ScratchPad << y.yield(1)
        end.to_a

        ScratchPad.recorded.should == [nil]
      end

      it 'accepts keyword arguments and treats them as a positional hash' do
        Enumerator.new { |y| y.yield(foo: 42) }.to_a.should == [{ foo: 42 }]
        Enumerator.new { |y| y.yield(foo: 42) }.first.should == { foo: 42 }

        Enumerator.new { |y| y.yield(123, foo: 42) }.to_a.should == [[123, { foo: 42 }]]
        Enumerator.new { |y| y.yield(123, foo: 42) }.first.should == [123, { foo: 42 }]
      end
    end

    describe '#<<' do
      it 'accepts a single argument' do
        Enumerator.new { |y| y.<<(1) }.to_a.should == [1]
        Enumerator.new { |y| y.<<(1) }.first.should == 1
      end

      it "doesn't double-wrap arrays" do
        Enumerator.new { |y| y.<<([1]) }.to_a.should == [[1]]
        Enumerator.new { |y| y.<<([1]) }.first.should == [1]

        Enumerator.new { |y| y.<<([1, 2]) }.to_a.should == [[1, 2]]
        Enumerator.new { |y| y.<<([1, 2]) }.first.should == [1, 2]
      end

      it 'accepts keyword arguments and treats them as a positional hash' do
        Enumerator.new { |y| y.<<(foo: 42) }.to_a.should == [{ foo: 42 }]
        Enumerator.new { |y| y.<<(foo: 42) }.first.should == { foo: 42 }
      end

      it 'can be chained' do
        enum = Enumerator.new do |y|
          y << 1 << 2
        end
        enum.to_a.should == [1, 2]
      end

      it 'raises ArgumentError when given more than one argument' do
        -> {
          Enumerator.new { |y| y.<<(1, 2) }.to_a
        }.should.raise(ArgumentError, "wrong number of arguments (given 2, expected 1)")
      end
    end
  end
end
