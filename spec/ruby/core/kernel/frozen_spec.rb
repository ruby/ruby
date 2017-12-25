require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../fixtures/classes', __FILE__)

describe "Kernel#frozen?" do
  it "returns true if self is frozen" do
    o = mock('o')
    p = mock('p')
    p.freeze
    o.frozen?.should == false
    p.frozen?.should == true
  end

  describe "on true, false and nil" do
    it "returns true" do
      true.frozen?.should be_true
      false.frozen?.should be_true
      nil.frozen?.should be_true
    end
  end

  describe "on integers" do
    before :each do
      @fixnum = 1
      @bignum = bignum_value
    end

    it "returns true" do
      @fixnum.frozen?.should be_true
      @bignum.frozen?.should be_true
    end
  end

  describe "on a Float" do
    before :each do
      @float = 0.1
    end

    it "returns true" do
      @float.frozen?.should be_true
    end
  end

  describe "on a Symbol" do
    before :each do
      @symbol = :symbol
    end

    it "returns true" do
      @symbol.frozen?.should be_true
    end
  end

  ruby_version_is "2.5" do
    describe "on a Complex" do
      it "returns true" do
        c = Complex(1.3, 3.1)
        c.frozen?.should be_true
      end

      it "literal returns true" do
        c = eval "1.3i"
        c.frozen?.should be_true
      end
    end

    describe "on a Rational" do
      it "returns true" do
        r = Rational(1, 3)
        r.frozen?.should be_true
      end

      it "literal returns true" do
        r = eval "1/3r"
        r.frozen?.should be_true
      end
    end
  end
end
