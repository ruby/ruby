require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#frozen?" do
  it "returns true if self is frozen" do
    o = mock('o')
    p = mock('p')
    p.freeze
    o.should_not.frozen?
    p.should.frozen?
  end

  describe "on true, false and nil" do
    it "returns true" do
      true.frozen?.should == true
      false.frozen?.should == true
      nil.frozen?.should == true
    end
  end

  describe "on integers" do
    before :each do
      @fixnum = 1
      @bignum = bignum_value
    end

    it "returns true" do
      @fixnum.frozen?.should == true
      @bignum.frozen?.should == true
    end
  end

  describe "on a Float" do
    before :each do
      @float = 0.1
    end

    it "returns true" do
      @float.frozen?.should == true
    end
  end

  describe "on a Symbol" do
    before :each do
      @symbol = :symbol
    end

    it "returns true" do
      @symbol.frozen?.should == true
    end
  end

  describe "on a Complex" do
    it "returns true" do
      c = Complex(1.3, 3.1)
      c.frozen?.should == true
    end

    it "literal returns true" do
      c = eval "1.3i"
      c.frozen?.should == true
    end
  end

  describe "on a Rational" do
    it "returns true" do
      r = Rational(1, 3)
      r.frozen?.should == true
    end

    it "literal returns true" do
      r = eval "1/3r"
      r.frozen?.should == true
    end
  end
end
