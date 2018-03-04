require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/process/fork'

describe "Kernel#fork" do
  it "is a private method" do
    Kernel.should have_private_instance_method(:fork)
  end

  it_behaves_like :process_fork, :fork, KernelSpecs::Method.new
end

describe "Kernel.fork" do
  it_behaves_like :process_fork, :fork, Kernel
end
