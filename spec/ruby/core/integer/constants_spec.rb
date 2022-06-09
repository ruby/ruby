require_relative '../../spec_helper'

describe "Fixnum" do
  ruby_version_is ""..."3.2" do
    it "is unified into Integer" do
      suppress_warning do
        Fixnum.should equal(Integer)
      end
    end

    it "is deprecated" do
      -> { Fixnum }.should complain(/constant ::Fixnum is deprecated/)
    end
  end

  ruby_version_is "3.2" do
    it "is no longer defined" do
      Object.should_not.const_defined?(:Fixnum)
    end
  end
end

describe "Bignum" do
  ruby_version_is ""..."3.2" do
    it "is unified into Integer" do
      suppress_warning do
        Bignum.should equal(Integer)
      end
    end

    it "is deprecated" do
      -> { Bignum }.should complain(/constant ::Bignum is deprecated/)
    end
  end

  ruby_version_is "3.2" do
    it "is no longer defined" do
      Object.should_not.const_defined?(:Bignum)
    end
  end
end
