require_relative '../../spec_helper'
require_relative 'shared/then'

describe "Kernel#then" do
  it_behaves_like :kernel_then, :then
end
