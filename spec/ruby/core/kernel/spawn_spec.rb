require_relative '../../spec_helper'
require_relative 'fixtures/classes'

# These specs only run a basic usage of #spawn.
# Process.spawn has more complete specs and they are not
# run here as it is redundant and takes too long for little gain.
describe "Kernel#spawn" do
  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:spawn)
  end

  it "executes the given command" do
    -> {
      Process.wait spawn("echo spawn")
    }.should output_to_fd("spawn\n")
  end
end

describe "Kernel.spawn" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:spawn)
  end
end
