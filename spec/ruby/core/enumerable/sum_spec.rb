require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'Enumerable#sum' do
  before :each do
    @enum = Object.new.to_enum
    class << @enum
      def each
        yield 0
        yield(-1)
        yield 2
        yield 2/3r
      end
    end
  end

  it 'returns amount of the elements with taking an argument as the initial value' do
    @enum.sum(10).should == 35/3r
  end

  it 'gives 0 as a default argument' do
    @enum.sum.should == 5/3r
  end

  context 'with a block' do
    it 'transforms the elements' do
      @enum.sum { |element| element * 2 }.should == 10/3r
    end

    it 'does not destructure array elements' do
      class << @enum
        def each
          yield [1,2]
          yield [3]
        end
      end

      @enum.sum(&:last).should == 5
    end
  end

  # https://bugs.ruby-lang.org/issues/12217
  # https://github.com/ruby/ruby/blob/master/doc/ChangeLog/ChangeLog-2.4.0#L6208-L6214
  it "uses Kahan's compensated summation algorithm for precise sum of float numbers" do
    floats = [2.7800000000000002, 5.0, 2.5, 4.44, 3.89, 3.89, 4.44, 7.78, 5.0, 2.7800000000000002, 5.0, 2.5].to_enum
    naive_sum = floats.reduce { |sum, e| sum + e }
    naive_sum.should == 50.00000000000001
    floats.sum.should == 50.0
  end
end
