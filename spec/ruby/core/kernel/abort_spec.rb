require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/process/abort'

describe "Kernel#abort" do
  it "is a private method" do
    Kernel.should have_private_instance_method(:abort)
  end

  it_behaves_like :process_abort, :abort, KernelSpecs::Method.new
end

describe "Kernel.abort" do
  it_behaves_like :process_abort, :abort, Kernel
end
