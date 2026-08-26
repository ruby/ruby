require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/process/abort'

describe "Kernel#abort" do
  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:abort)
  end

  it_behaves_like :process_abort, :abort, KernelSpecs::Method.new
end

describe "Kernel.abort" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:abort)
  end
end
