require_relative '../../spec_helper'
require_relative 'fixtures/classes'

# Should be synchronized with core/array/values_at_spec.rb
describe "Struct#values_at" do
  before do
    clazz = Struct.new(:name, :director, :year)
    @movie = clazz.new('Sympathy for Mr. Vengeance', 'Chan-wook Park', 2002)
  end

  context "when passed a list of Integers" do
    it "returns an array containing each value given by one of integers" do
      @movie.values_at(0, 1).should == ['Sympathy for Mr. Vengeance', 'Chan-wook Park']
    end

    it "raises IndexError if any of integers is out of range" do
      -> { @movie.values_at(3) }.should raise_error(IndexError, "offset 3 too large for struct(size:3)")
      -> { @movie.values_at(-4) }.should raise_error(IndexError, "offset -4 too small for struct(size:3)")
    end
  end

  context "when passed an integer Range" do
    it "returns an array containing each value given by the elements of the range" do
      @movie.values_at(0..2).should == ['Sympathy for Mr. Vengeance', 'Chan-wook Park', 2002]
    end

    it "fills with nil values for range elements larger than the structure" do
      @movie.values_at(0..3).should == ['Sympathy for Mr. Vengeance', 'Chan-wook Park', 2002, nil]
    end

    it "raises RangeError if any element of the range is negative and out of range" do
      -> { @movie.values_at(-4..3) }.should raise_error(RangeError, "-4..3 out of range")
    end

    it "supports endless Range" do
      @movie.values_at(0..).should == ["Sympathy for Mr. Vengeance", "Chan-wook Park", 2002]
    end

    it "supports beginningless Range" do
      @movie.values_at(..2).should == ["Sympathy for Mr. Vengeance", "Chan-wook Park", 2002]
    end
  end

  it "supports multiple integer Ranges" do
    @movie.values_at(0..2, 1..2).should == ['Sympathy for Mr. Vengeance', 'Chan-wook Park', 2002, 'Chan-wook Park', 2002]
  end

  it "supports mixing integer Ranges and Integers" do
    @movie.values_at(0..2, 2).should == ['Sympathy for Mr. Vengeance', 'Chan-wook Park', 2002, 2002]
  end

  it "returns a new empty Array if no arguments given" do
    @movie.values_at().should == []
  end

  it "fails when passed unsupported types" do
    -> { @movie.values_at('make') }.should raise_error(TypeError, "no implicit conversion of String into Integer")
  end
end
