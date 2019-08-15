require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#readlines" do
  it "is a private method" do
    Kernel.should have_private_instance_method(:readlines)
  end
end

describe "Kernel.readlines" do
  it "needs to be reviewed for spec completeness"
end
