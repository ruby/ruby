require_relative '../../spec_helper'
require_relative 'shared/end'

describe "Range#end" do
  it_behaves_like :range_end, :end
end
