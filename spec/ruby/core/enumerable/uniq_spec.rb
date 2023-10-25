require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'Enumerable#uniq' do
  it 'returns an array that contains only unique elements' do
    [0, 1, 2, 3].to_enum.uniq { |n| n.even? }.should == [0, 1]
  end

  it "uses eql? semantics" do
    [1.0, 1].to_enum.uniq.should == [1.0, 1]
  end

  it "compares elements first with hash" do
    x = mock('0')
    x.should_receive(:hash).at_least(1).and_return(0)
    y = mock('0')
    y.should_receive(:hash).at_least(1).and_return(0)

    [x, y].to_enum.uniq.should == [x, y]
  end

  it "does not compare elements with different hash codes via eql?" do
    x = mock('0')
    x.should_not_receive(:eql?)
    y = mock('1')
    y.should_not_receive(:eql?)

    x.should_receive(:hash).at_least(1).and_return(0)
    y.should_receive(:hash).at_least(1).and_return(1)

    [x, y].to_enum.uniq.should == [x, y]
  end

  it "compares elements with matching hash codes with #eql?" do
    a = Array.new(2) do
      obj = mock('0')
      obj.should_receive(:hash).at_least(1).and_return(0)

      def obj.eql?(o)
        false
      end

      obj
    end

    a.uniq.should == a

    a = Array.new(2) do
      obj = mock('0')
      obj.should_receive(:hash).at_least(1).and_return(0)

      def obj.eql?(o)
        true
      end

      obj
    end

    a.to_enum.uniq.size.should == 1
  end

  context 'when yielded with multiple arguments' do
    before :each do
      @enum = Object.new.to_enum
      class << @enum
        def each
          yield 0, 'foo'
          yield 1, 'FOO'
          yield 2, 'bar'
        end
      end
    end

    it 'returns all yield arguments as an array' do
      @enum.uniq { |_, label| label.downcase }.should == [[0, 'foo'], [2, 'bar']]
    end
  end
end
