require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#path" do
  it "is not defined" do
    lambda { StringIO.new("path").path }.should raise_error(NoMethodError)
  end
end
