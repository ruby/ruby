require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'Comparable#clamp' do
  it 'raises an Argument error unless given 2 parameters' do
    c = ComparableSpecs::Weird.new(0)
    -> { c.clamp(c) }.should raise_error(ArgumentError)
    -> { c.clamp(c, c, c) }.should raise_error(ArgumentError)
  end

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

  it 'returns the min parameter if smaller than it' do
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
end
