require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe "Delegator#untaint" do
  before :each do
    @delegate = -> { DelegateSpecs::Delegator.new("") }.call
  end
end
