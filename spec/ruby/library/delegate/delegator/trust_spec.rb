require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe "Delegator#trust" do
  before :each do
    @delegate = DelegateSpecs::Delegator.new([])
  end
end
