require_relative '../../spec_helper'
require_relative 'shared/select'

describe "Set#select!" do
  it_behaves_like :set_select_bang, :select!
end
