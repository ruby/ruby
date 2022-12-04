require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe "Delegator#untrust" do
  before :each do
    @delegate = DelegateSpecs::Delegator.new("")
  end
end
