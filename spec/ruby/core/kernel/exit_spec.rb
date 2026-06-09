require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/process/exit'

describe "Kernel#exit" do
  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:exit)
  end

  it_behaves_like :process_exit, :exit, KernelSpecs::Method.new
end

describe "Kernel.exit" do
  it_behaves_like :process_exit, :exit, Kernel
end

describe "Kernel#exit!" do
  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:exit!)
  end

  it_behaves_like :process_exit!, :exit!, "self"
end

describe "Kernel.exit!" do
  it_behaves_like :process_exit!, :exit!, "Kernel"
end
