require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe "Delegator#untrust" do
  before :each do
    @delegate = DelegateSpecs::Delegator.new("")
  end

  ruby_version_is ''...'2.7' do
    it "returns self" do
      @delegate.untrust.equal?(@delegate).should be_true
    end

    it "untrusts the delegator" do
      @delegate.__setobj__(nil)
      @delegate.untrust
      @delegate.untrusted?.should be_true
    end

    it "untrusts the delegated object" do
      @delegate.untrust
      @delegate.__getobj__.untrusted?.should be_true
    end
  end
end
