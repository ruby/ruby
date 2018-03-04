require_relative '../../spec_helper'
require_relative 'shared/kind_of'

describe "Kernel#is_a?" do
  it_behaves_like :kernel_kind_of , :is_a?
end
