require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/kernel/at_exit'

describe "Kernel#at_exit" do
  it_behaves_like :kernel_at_exit, :at_exit

  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:at_exit)
  end

  it "raises ArgumentError if called without a block" do
    -> { at_exit }.should.raise(ArgumentError, "called without a block")
  end
end

describe "Kernel.at_exit" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:at_exit)
  end
end
