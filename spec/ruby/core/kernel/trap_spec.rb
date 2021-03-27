require_relative '../../spec_helper'

describe "Kernel#trap" do
  it "is a private method" do
    Kernel.should have_private_instance_method(:trap)
  end

  # Behaviour is specified for Signal.trap
end
