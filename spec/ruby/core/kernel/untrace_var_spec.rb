require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#untrace_var" do
  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:untrace_var)
  end
end

describe "Kernel.untrace_var" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:untrace_var)
  end
end
