require_relative '../../spec_helper'
require_relative 'shared/to_s'
require_relative 'shared/aliased_inspect'

describe "Method#inspect" do
  it_behaves_like :method_to_s, :inspect
  it_behaves_like :method_to_s_aliased, :inspect, -> meth { meth }
end
