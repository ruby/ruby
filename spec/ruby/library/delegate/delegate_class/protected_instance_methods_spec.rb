require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe "DelegateClass.protected_instance_methods" do
  before :all do
    @methods = DelegateSpecs::DelegateClass.protected_instance_methods
  end

  it "does not include public methods of the delegated class" do
    @methods.should_not include :pub
  end

  it "includes the protected methods of the delegated class" do
    @methods.should include :prot
  end

  it "includes protected instance methods of the DelegateClass class" do
    @methods.should include :extra_protected
  end

  it "does not include public instance methods of the DelegateClass class" do
    @methods.should_not include :extra
  end

  it "does not include private methods" do
    @methods.should_not include :priv
    @methods.should_not include :extra_private
  end
end
