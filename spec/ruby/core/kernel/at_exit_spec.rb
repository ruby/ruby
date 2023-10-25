require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/kernel/at_exit'

describe "Kernel.at_exit" do
  it_behaves_like :kernel_at_exit, :at_exit

  it "is a private method" do
    Kernel.should have_private_instance_method(:at_exit)
  end

  it "raises ArgumentError if called without a block" do
    -> { at_exit }.should raise_error(ArgumentError, "called without a block")
  end
end

describe "Kernel#at_exit" do
  it "needs to be reviewed for spec completeness"
end
