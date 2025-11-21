require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'Comparable#clamp' do
  it 'raises an Argument error unless the 2 parameters are correctly ordered' do
    one = ComparableSpecs::WithOnlyCompareDefined.new(1)
    two = ComparableSpecs::WithOnlyCompareDefined.new(2)
    c = ComparableSpecs::Weird.new(3)

    -> { c.clamp(two, one) }.should raise_error(ArgumentError)
    one.should_receive(:<=>).any_number_of_times.and_return(nil)
    -> { c.clamp(one, two) }.should raise_error(ArgumentError)
  end

  it 'returns self if within the given parameters' do
    one = ComparableSpecs::WithOnlyCompareDefined.new(1)
    two = ComparableSpecs::WithOnlyCompareDefined.new(2)
    three = ComparableSpecs::WithOnlyCompareDefined.new(3)
    c = ComparableSpecs::Weird.new(2)

    c.clamp(one, two).should equal(c)
    c.clamp(two, two).should equal(c)
    c.clamp(one, three).should equal(c)
    c.clamp(two, three).should equal(c)
  end

  it 'returns the min parameter if less than it' do
    one = ComparableSpecs::WithOnlyCompareDefined.new(1)
    two = ComparableSpecs::WithOnlyCompareDefined.new(2)
    c = ComparableSpecs::Weird.new(0)

    c.clamp(one, two).should equal(one)
  end

  it 'returns the max parameter if greater than it' do
    one = ComparableSpecs::WithOnlyCompareDefined.new(1)
    two = ComparableSpecs::WithOnlyCompareDefined.new(2)
    c = ComparableSpecs::Weird.new(3)

    c.clamp(one, two).should equal(two)
  end

  it 'returns self if within the given range parameters' do
    one = ComparableSpecs::WithOnlyCompareDefined.new(1)
    two = ComparableSpecs::WithOnlyCompareDefined.new(2)
    three = ComparableSpecs::WithOnlyCompareDefined.new(3)
    c = ComparableSpecs::Weird.new(2)

    c.clamp(one..two).should equal(c)
    c.clamp(two..two).should equal(c)
    c.clamp(one..three).should equal(c)
    c.clamp(two..three).should equal(c)
  end

  it 'returns the minimum value of the range parameters if less than it' do
    one = ComparableSpecs::WithOnlyCompareDefined.new(1)
    two = ComparableSpecs::WithOnlyCompareDefined.new(2)
    c = ComparableSpecs::Weird.new(0)

    c.clamp(one..two).should equal(one)
  end

  it 'returns the maximum value of the range parameters if greater than it' do
    one = ComparableSpecs::WithOnlyCompareDefined.new(1)
    two = ComparableSpecs::WithOnlyCompareDefined.new(2)
    c = ComparableSpecs::Weird.new(3)

    c.clamp(one..two).should equal(two)
  end

  it 'raises an Argument error if the range parameter is exclusive' do
    one = ComparableSpecs::WithOnlyCompareDefined.new(1)
    two = ComparableSpecs::WithOnlyCompareDefined.new(2)
    c = ComparableSpecs::Weird.new(3)

    -> { c.clamp(one...two) }.should raise_error(ArgumentError)
  end

  context 'with endless range' do
    it 'returns minimum value of the range parameters if less than it' do
      one = ComparableSpecs::WithOnlyCompareDefined.new(1)
      zero = ComparableSpecs::WithOnlyCompareDefined.new(0)
      c = ComparableSpecs::Weird.new(0)

      c.clamp(one..).should equal(one)
      c.clamp(zero..).should equal(c)
    end

    it 'always returns self if greater than minimum value of the range parameters' do
      one = ComparableSpecs::WithOnlyCompareDefined.new(1)
      two = ComparableSpecs::WithOnlyCompareDefined.new(2)
      c = ComparableSpecs::Weird.new(2)

      c.clamp(one..).should equal(c)
      c.clamp(two..).should equal(c)
    end

    it 'works with exclusive range' do
      one = ComparableSpecs::WithOnlyCompareDefined.new(1)
      c = ComparableSpecs::Weird.new(2)

      c.clamp(one...).should equal(c)
    end
  end

  context 'with beginless range' do
    it 'returns maximum value of the range parameters if greater than it' do
      one = ComparableSpecs::WithOnlyCompareDefined.new(1)
      c = ComparableSpecs::Weird.new(2)

      c.clamp(..one).should equal(one)
    end

    it 'always returns self if less than maximum value of the range parameters' do
      one = ComparableSpecs::WithOnlyCompareDefined.new(1)
      zero = ComparableSpecs::WithOnlyCompareDefined.new(0)
      c = ComparableSpecs::Weird.new(0)

      c.clamp(..one).should equal(c)
      c.clamp(..zero).should equal(c)
    end

    it 'raises an Argument error if the range parameter is exclusive' do
      one = ComparableSpecs::WithOnlyCompareDefined.new(1)
      c = ComparableSpecs::Weird.new(0)

      -> { c.clamp(...one) }.should raise_error(ArgumentError)
    end
  end

  context 'with beginless-and-endless range' do
    it 'always returns self' do
      c = ComparableSpecs::Weird.new(1)

      c.clamp(nil..nil).should equal(c)
    end

    it 'works with exclusive range' do
      c = ComparableSpecs::Weird.new(2)

      c.clamp(nil...nil).should equal(c)
    end
  end
end
