# encoding: binary
require_relative '../../spec_helper'

describe "Encoding#replicate" do
  it "has been removed" do
    Encoding::US_ASCII.should_not.respond_to?(:replicate, true)
  end
end
