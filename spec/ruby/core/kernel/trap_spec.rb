require_relative '../../spec_helper'

describe "Kernel#trap" do
  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:trap)
  end

  # Behaviour is specified for Signal.trap
end
