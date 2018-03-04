require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#freeze" do
  it "prevents self from being further modified" do
    o = mock('o')
    o.frozen?.should be_false
    o.freeze
    o.frozen?.should be_true
  end

  it "returns self" do
    o = Object.new
    o.freeze.should equal(o)
  end

  describe "on integers" do
    it "has no effect since they are already frozen" do
      1.frozen?.should be_true
      1.freeze

      bignum = bignum_value
      bignum.frozen?.should be_true
      bignum.freeze
    end
  end

  describe "on a Float" do
    it "has no effect since it is already frozen" do
      1.2.frozen?.should be_true
      1.2.freeze
    end
  end

  describe "on a Symbol" do
    it "has no effect since it is already frozen" do
      :sym.frozen?.should be_true
      :sym.freeze
    end
  end

  describe "on true, false and nil" do
    it "has no effect since they are already frozen" do
      nil.frozen?.should be_true
      true.frozen?.should be_true
      false.frozen?.should be_true

      nil.freeze
      true.freeze
      false.freeze
    end
  end

  ruby_version_is "2.5" do
    describe "on a Complex" do
      it "has no effect since it is already frozen" do
        c = Complex(1.3, 3.1)
        c.frozen?.should be_true
        c.freeze
      end
    end

    describe "on a Rational" do
      it "has no effect since it is already frozen" do
        r = Rational(1, 3)
        r.frozen?.should be_true
        r.freeze
      end
    end
  end

  it "causes mutative calls to raise RuntimeError" do
    o = Class.new do
      def mutate; @foo = 1; end
    end.new
    o.freeze
    lambda {o.mutate}.should raise_error(RuntimeError)
  end

  it "causes instance_variable_set to raise RuntimeError" do
    o = Object.new
    o.freeze
    lambda {o.instance_variable_set(:@foo, 1)}.should raise_error(RuntimeError)
  end
end
