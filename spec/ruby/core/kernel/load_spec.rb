require_relative '../../spec_helper'
require_relative '../../fixtures/code_loading'
require_relative 'shared/load'
require_relative 'shared/require'

describe "Kernel#load" do
  before :each do
    CodeLoadingSpecs.spec_setup
  end

  after :each do
    CodeLoadingSpecs.spec_cleanup
  end

  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:load)
  end

  it_behaves_like :kernel_require_basic, :load, CodeLoadingSpecs::Method.new
end

describe "Kernel#load" do
  it_behaves_like :kernel_load, :load, CodeLoadingSpecs::Method.new
end

describe "Kernel.load" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:load)
  end
end
