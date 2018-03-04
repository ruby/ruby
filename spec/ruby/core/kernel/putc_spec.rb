require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/io/putc'

describe "Kernel#putc" do
  it "is a private instance method" do
    Kernel.should have_private_instance_method(:putc)
  end
end

describe "Kernel.putc" do
  before :each do
    @name = tmp("kernel_putc.txt")
    @io = new_io @name
    @io_object = @object
    @stdout, $stdout = $stdout, @io
  end

  after :each do
    $stdout = @stdout
  end

  it_behaves_like :io_putc, :putc_method, KernelSpecs
end

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

  it_behaves_like :io_putc, :putc_function, KernelSpecs
end
