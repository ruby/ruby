require_relative '../../spec_helper'

describe "Enumerator.new" do
  context "no block given" do
    ruby_version_is '2.8' do
      it "raises" do
        -> { Enumerator.new(1, :upto, 3) }.should raise_error(ArgumentError)
      end
    end

    ruby_version_is ''...'2.8' do
      it "creates a new custom enumerator with the given object, iterator and arguments" do
        enum = Enumerator.new(1, :upto, 3)
        enum.should be_an_instance_of(Enumerator)
      end

      it "creates a new custom enumerator that responds to #each" do
        enum = Enumerator.new(1, :upto, 3)
        enum.respond_to?(:each).should == true
      end

      it "creates a new custom enumerator that runs correctly" do
        Enumerator.new(1, :upto, 3).map{|x|x}.should == [1,2,3]
      end

      it "aliases the second argument to :each" do
        Enumerator.new(1..2).to_a.should == Enumerator.new(1..2, :each).to_a
      end

      it "doesn't check for the presence of the iterator method" do
        Enumerator.new(nil).should be_an_instance_of(Enumerator)
      end

      it "uses the latest define iterator method" do
        class StrangeEach
          def each
            yield :foo
          end
        end
        enum = Enumerator.new(StrangeEach.new)
        enum.to_a.should == [:foo]
        class StrangeEach
          def each
            yield :bar
          end
        end
        enum.to_a.should == [:bar]
      end
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

    ruby_version_is "2.7" do
      it "defines iteration with block, yielder argument and treating it as a proc" do
        enum = Enumerator.new do |yielder|
          "a\nb\nc".each_line(&yielder)
        end

        enum.to_a.should == ["a\n", "b\n", "c"]
      end
    end

    describe 'yielded values' do
      it 'handles yield arguments properly' do
        Enumerator.new { |y| y.yield(1) }.to_a.should == [1]
        Enumerator.new { |y| y.yield(1) }.first.should == 1

        Enumerator.new { |y| y.yield([1]) }.to_a.should == [[1]]
        Enumerator.new { |y| y.yield([1]) }.first.should == [1]

        Enumerator.new { |y| y.yield(1, 2) }.to_a.should == [[1, 2]]
        Enumerator.new { |y| y.yield(1, 2) }.first.should == [1, 2]

        Enumerator.new { |y| y.yield([1, 2]) }.to_a.should == [[1, 2]]
        Enumerator.new { |y| y.yield([1, 2]) }.first.should == [1, 2]
      end

      it 'handles << arguments properly' do
        Enumerator.new { |y| y.<<(1) }.to_a.should == [1]
        Enumerator.new { |y| y.<<(1) }.first.should == 1

        Enumerator.new { |y| y.<<([1]) }.to_a.should == [[1]]
        Enumerator.new { |y| y.<<([1]) }.first.should == [1]

        # << doesn't accept multiple arguments
        # Enumerator.new { |y| y.<<(1, 2) }.to_a.should == [[1, 2]]
        # Enumerator.new { |y| y.<<(1, 2) }.first.should == [1, 2]

        Enumerator.new { |y| y.<<([1, 2]) }.to_a.should == [[1, 2]]
        Enumerator.new { |y| y.<<([1, 2]) }.first.should == [1, 2]
      end
    end
  end
end
