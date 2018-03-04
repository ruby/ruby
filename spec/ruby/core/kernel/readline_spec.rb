require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#readline" do
  it "is a private method" do
    Kernel.should have_private_instance_method(:readline)
  end
end

describe "Kernel.readline" do
  it "needs to be reviewed for spec completeness"
end
