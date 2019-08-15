require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Numeric#coerce" do
  before :each do
    @obj = NumericSpecs::Subclass.new
    @obj.should_receive(:to_f).any_number_of_times.and_return(10.5)
  end

  it "returns [other, self] if self and other are instances of the same class" do
    a = NumericSpecs::Subclass.new
    b = NumericSpecs::Subclass.new

    a.coerce(b).should == [b, a]
  end

  # I (emp) think that this behavior is actually a bug in MRI. It's here as documentation
  # of the behavior until we find out if it's a bug.
  quarantine! do
    it "considers the presence of a metaclass when checking the class of the objects" do
      a = NumericSpecs::Subclass.new
      b = NumericSpecs::Subclass.new

      # inject a metaclass on a
      class << a; true; end

      # watch it explode
      -> { a.coerce(b) }.should raise_error(TypeError)
    end
  end

  it "returns [other.to_f, self.to_f] if self and other are instances of different classes" do
    @obj.coerce(2.5).should == [2.5, 10.5]
    @obj.coerce(3).should == [3.0, 10.5]
    @obj.coerce("4.4").should == [4.4, 10.5]
    @obj.coerce(bignum_value).should == [bignum_value.to_f, 10.5]
  end

  it "raise TypeError if they are instances of different classes and other does not respond to #to_f" do
    other = mock("numeric")
    -> { @obj.coerce(other)   }.should raise_error(TypeError)
  end

  it "raises a TypeError when passed nil" do
    -> { @obj.coerce(nil)     }.should raise_error(TypeError)
  end

  it "raises a TypeError when passed a boolean" do
    -> { @obj.coerce(false)   }.should raise_error(TypeError)
  end

  it "raises a TypeError when passed a Symbol" do
    -> { @obj.coerce(:symbol) }.should raise_error(TypeError)
  end

  it "raises an ArgumentError when passed a non-numeric String" do
    -> { @obj.coerce("test")  }.should raise_error(ArgumentError)
  end
end
