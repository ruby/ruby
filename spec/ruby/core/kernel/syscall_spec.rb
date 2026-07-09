require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#syscall" do
  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:syscall)
  end
end

describe "Kernel.syscall" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:syscall)
  end
end
