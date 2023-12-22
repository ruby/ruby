require_relative '../../spec_helper'
require_relative 'shared/new'

# NOTE: should be synchronized with library/stringio/initialize_spec.rb

describe "IO.new" do
  it_behaves_like :io_new, :new

  it "does not use the given block and warns to use IO::open" do
    -> {
      @io = IO.send(@method, @fd) { raise }
    }.should complain(/warning: IO::new\(\) does not take block; use IO::open\(\) instead/)
  end
end

describe "IO.new" do
  it_behaves_like :io_new_errors, :new
end
