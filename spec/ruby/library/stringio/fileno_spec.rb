require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/each'

describe "StringIO#fileno" do
  it "returns nil" do
    StringIO.new("nuffin").fileno.should be_nil
  end
end
