require_relative '../../spec_helper'

ruby_version_is ""..."2.7" do
  describe "Fixnum" do
    it "is unified into Integer" do
      suppress_warning do
        Fixnum.should equal(Integer)
      end
    end

    it "is deprecated" do
      -> { Fixnum }.should complain(/constant ::Fixnum is deprecated/)
    end
  end

  describe "Bignum" do
    it "is unified into Integer" do
      suppress_warning do
        Bignum.should equal(Integer)
      end
    end

    it "is deprecated" do
      -> { Bignum }.should complain(/constant ::Bignum is deprecated/)
    end
  end
end
