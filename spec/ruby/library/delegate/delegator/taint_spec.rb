require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe "Delegator#taint" do
  before :each do
    @delegate = DelegateSpecs::Delegator.new("")
  end
end
