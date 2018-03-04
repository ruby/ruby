require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#pid" do
  it "returns nil" do
    StringIO.new("pid").pid.should be_nil
  end
end
