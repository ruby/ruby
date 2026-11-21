require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/io/putc'

describe "Kernel#putc" do
  before :each do
    @name = tmp("kernel_putc.txt")
    @io = new_io @name
    @io_object = @object
    @stdout, $stdout = $stdout, @io
  end

  after :each do
    $stdout = @stdout
  end

  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:putc)
  end

  it_behaves_like :io_putc, :putc, Object.new
end

describe "Kernel.putc" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:putc)
  end
end
