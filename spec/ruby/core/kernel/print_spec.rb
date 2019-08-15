require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#print" do
  it "is a private method" do
    Kernel.should have_private_instance_method(:print)
  end
end

describe "Kernel.print" do
  it "needs to be reviewed for spec completeness"
end
