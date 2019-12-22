require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe "Delegator#trust" do
  before :each do
    @delegate = DelegateSpecs::Delegator.new([])
  end

  ruby_version_is ''...'2.7' do
    it "returns self" do
      @delegate.trust.equal?(@delegate).should be_true
    end

    it "trusts the delegator" do
      @delegate.trust
      @delegate.untrusted?.should be_false
    end

    it "trusts the delegated object" do
      @delegate.trust
      @delegate.__getobj__.untrusted?.should be_false
    end
  end
end
