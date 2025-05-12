require_relative '../../spec_helper'
require_relative 'shared/select'

describe "Set#filter!" do
  it_behaves_like :set_select_bang, :filter!
end
