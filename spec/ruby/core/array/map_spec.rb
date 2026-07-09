require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../enumerable/shared/enumeratorized'
require_relative 'shared/iterable_and_tolerating_size_increasing'

describe "Array#map" do
  it "returns a copy of array with each element replaced by the value returned by block" do
    a = ['a', 'b', 'c', 'd']
    b = a.map { |i| i + '!' }
    b.should == ["a!", "b!", "c!", "d!"]
    b.should_not.equal? a
  end

  it "does not return subclass instance" do
    ArraySpecs::MyArray[1, 2, 3].map { |x| x + 1 }.should.instance_of?(Array)
  end

  it "does not change self" do
    a = ['a', 'b', 'c', 'd']
    a.map { |i| i + '!' }
    a.should == ['a', 'b', 'c', 'd']
  end

  it "returns the evaluated value of block if it broke in the block" do
    a = ['a', 'b', 'c', 'd']
    b = a.map {|i|
      if i == 'c'
        break 0
      else
        i + '!'
      end
    }
    b.should == 0
  end

  it "returns an Enumerator when no block given" do
    a = [1, 2, 3]
    a.map.should.instance_of?(Enumerator)
  end

  it "raises an ArgumentError when no block and with arguments" do
    a = [1, 2, 3]
    -> {
      a.map(:foo)
    }.should.raise(ArgumentError)
  end

  before :each do
    @object = [1, 2, 3, 4]
  end
  it_behaves_like :enumeratorized_with_origin_size, :map

  it_behaves_like :array_iterable_and_tolerating_size_increasing, :map
end

describe "Array#map!" do
  it "replaces each element with the value returned by block" do
    a = [7, 9, 3, 5]
    a.map! { |i| i - 1 }.should.equal?(a)
    a.should == [6, 8, 2, 4]
  end

  it "returns self" do
    a = [1, 2, 3, 4, 5]
    b = a.map! {|i| i+1 }
    a.should.equal? b
  end

  it "returns the evaluated value of block but its contents is partially modified, if it broke in the block" do
    a = ['a', 'b', 'c', 'd']
    b = a.map! {|i|
      if i == 'c'
        break 0
      else
        i + '!'
      end
    }
    b.should == 0
    a.should == ['a!', 'b!', 'c', 'd']
  end

  it "returns an Enumerator when no block given, and the enumerator can modify the original array" do
    a = [1, 2, 3]
    enum = a.map!
    enum.should.instance_of?(Enumerator)
    enum.each{|i| "#{i}!" }
    a.should == ["1!", "2!", "3!"]
  end

  describe "when frozen" do
    it "raises a FrozenError" do
      -> { ArraySpecs.frozen_array.map! {} }.should.raise(FrozenError)
    end

    it "raises a FrozenError when empty" do
      -> { ArraySpecs.empty_frozen_array.map! {} }.should.raise(FrozenError)
    end

    it "raises a FrozenError when calling #each on the returned Enumerator" do
      enumerator = ArraySpecs.frozen_array.map!
      -> { enumerator.each {|x| x } }.should.raise(FrozenError)
    end

    it "raises a FrozenError when calling #each on the returned Enumerator when empty" do
      enumerator = ArraySpecs.empty_frozen_array.map!
      -> { enumerator.each {|x| x } }.should.raise(FrozenError)
    end
  end

  it "does not truncate the array is the block raises an exception" do
    a = [1, 2, 3]
    begin
      a.map! { raise StandardError, 'Oops' }
    rescue
    end

    a.should == [1, 2, 3]
  end

  it "only changes elements before error is raised, keeping the element which raised an error." do
    a = [1, 2, 3, 4]
    begin
      a.map! do |e|
        case e
        when 1 then -1
        when 2 then -2
        when 3 then raise StandardError, 'Oops'
        else 0
        end
      end
    rescue StandardError
    end

    a.should == [-1, -2, 3, 4]
  end

  before :each do
    @object = [1, 2, 3, 4]
  end
  it_behaves_like :enumeratorized_with_origin_size, :map!

  it_behaves_like :array_iterable_and_tolerating_size_increasing, :map!
end
