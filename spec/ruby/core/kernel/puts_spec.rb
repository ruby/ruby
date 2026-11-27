require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#puts" do
  before :each do
    @stdout = $stdout
    @name = tmp("kernel_puts.txt")
    $stdout = new_io @name
  end

  after :each do
    $stdout.close
    $stdout = @stdout
    rm_r @name
  end

  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:puts)
  end

  it "delegates to $stdout.puts" do
    $stdout.should_receive(:puts).with(:arg)
    puts :arg
  end
end

describe "Kernel.puts" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:puts)
  end
end
