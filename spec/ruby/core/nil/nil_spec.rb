require_relative '../../spec_helper'

describe "NilClass#nil?" do
  it "returns true" do
    nil.should.nil?
  end
end
