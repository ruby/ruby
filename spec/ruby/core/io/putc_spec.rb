require_relative '../../spec_helper'
require_relative '../../shared/io/putc'

describe "IO#putc" do
  before :each do
    @name = tmp("io_putc.txt")
    @io_object = @io = new_io(@name)
  end

  it_behaves_like :io_putc, :putc
end
