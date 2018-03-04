require_relative '../../spec_helper'
require_relative 'shared/new'

describe "IO.for_fd" do
  it_behaves_like :io_new, :for_fd
end

describe "IO.for_fd" do
  it_behaves_like :io_new_errors, :for_fd
end
