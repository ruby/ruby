require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Array#clear" do
  it "removes all elements" do
    a = [1, 2, 3, 4]
    a.clear.should equal(a)
    a.should == []
  end

  it "returns self" do
    a = [1]
    a.should equal a.clear
  end

  it "leaves the Array empty" do
    a = [1]
    a.clear
    a.empty?.should == true
    a.size.should == 0
  end

  ruby_version_is ''...'2.7' do
    it "keeps tainted status" do
      a = [1]
      a.taint
      a.tainted?.should be_true
      a.clear
      a.tainted?.should be_true
    end
  end

  it "does not accept any arguments" do
    -> { [1].clear(true) }.should raise_error(ArgumentError)
  end

  ruby_version_is ''...'2.7' do
    it "keeps untrusted status" do
      a = [1]
      a.untrust
      a.untrusted?.should be_true
      a.clear
      a.untrusted?.should be_true
    end
  end

  it "raises a #{frozen_error_class} on a frozen array" do
    a = [1]
    a.freeze
    -> { a.clear }.should raise_error(frozen_error_class)
  end
end
