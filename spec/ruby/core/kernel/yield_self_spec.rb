require_relative '../../spec_helper'
require_relative 'shared/then'

describe "Kernel#yield_self" do
  it_behaves_like :kernel_then, :yield_self
end
