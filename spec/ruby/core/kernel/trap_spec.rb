require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#trap" do
  it "is a private method" do
    Kernel.should have_private_instance_method(:trap)
  end
end

describe "Kernel.trap" do
  it "needs to be reviewed for spec completeness"
end
