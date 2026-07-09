require_relative '../spec_helper'

describe "The not keyword" do
  it "negates a `true' value" do
    (not true).should == false
    (not 'true').should == false
  end

  it "negates a `false' value" do
    (not false).should == true
    (not nil).should == true
  end

  it "accepts an argument" do
    not(true).should == false
  end

  it "returns false if the argument is true" do
    (not(true)).should == false
  end

  it "returns true if the argument is false" do
    (not(false)).should == true
  end

  it "returns true if the argument is nil" do
    (not(nil)).should == true
  end
end

describe "The `!' keyword" do
  it "negates a `true' value" do
    (!true).should == false
    (!'true').should == false
  end

  it "negates a `false' value" do
    (!false).should == true
    (!nil).should == true
  end

  it "doubled turns a truthful object into `true'" do
    (!!true).should == true
    (!!'true').should == true
  end

  it "doubled turns a not truthful object into `false'" do
    (!!false).should == false
    (!!nil).should == false
  end
end
