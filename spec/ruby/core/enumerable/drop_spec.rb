require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/value_packing'

describe "Enumerable#drop" do
  describe "value packing of source yields" do
    before :each do
      @take = -> e { e.drop(0) }
    end
    it_behaves_like :enumerable_value_packing, nil
  end

  before :each do
    @enum = EnumerableSpecs::Numerous.new(3, 2, 1, :go)
  end

  it "requires exactly one argument" do
    ->{ @enum.drop{} }.should.raise(ArgumentError)
    ->{ @enum.drop(1, 2){} }.should.raise(ArgumentError)
  end

  describe "passed a number n as an argument" do
    it "raises ArgumentError if n < 0" do
      ->{ @enum.drop(-1) }.should.raise(ArgumentError)
    end

    it "tries to convert n to an Integer using #to_int" do
      @enum.drop(2.3).should == [1, :go]

      obj = mock('to_int')
      obj.should_receive(:to_int).and_return(2)
      @enum.drop(obj).should == [1, :go]
    end

    it "returns [] for empty enumerables" do
      EnumerableSpecs::Empty.new.drop(0).should == []
      EnumerableSpecs::Empty.new.drop(2).should == []
    end

    it "returns [] if dropping all" do
      @enum.drop(5).should == []
      EnumerableSpecs::Numerous.new(3, 2, 1, :go).drop(4).should == []
    end

    it "raises a TypeError when the passed n cannot be coerced to Integer" do
      ->{ @enum.drop("hat") }.should.raise(TypeError)
      ->{ @enum.drop(nil) }.should.raise(TypeError)
    end

  end
end
