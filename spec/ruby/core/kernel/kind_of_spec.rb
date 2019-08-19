require_relative '../../spec_helper'
require_relative 'shared/kind_of'

describe "Kernel#kind_of?" do
  it_behaves_like :kernel_kind_of , :kind_of?
end
