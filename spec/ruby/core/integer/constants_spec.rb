require_relative '../../spec_helper'

describe "Fixnum" do
  before :each do
    if Warning.respond_to?(:[])
      @deprecated = Warning[:deprecated]
      Warning[:deprecated] = true
    end
  end

  after :each do
    if Warning.respond_to?(:[])
      Warning[:deprecated] = @deprecated
    end
  end

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
  before :each do
    if Warning.respond_to?(:[])
      @deprecated = Warning[:deprecated]
      Warning[:deprecated] = true
    end
  end

  after :each do
    if Warning.respond_to?(:[])
      Warning[:deprecated] = @deprecated
    end
  end

  it "is unified into Integer" do
    suppress_warning do
      Bignum.should equal(Integer)
    end
  end

  it "is deprecated" do
    -> { Bignum }.should complain(/constant ::Bignum is deprecated/)
  end
end
