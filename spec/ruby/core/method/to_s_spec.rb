require_relative '../../spec_helper'
require_relative 'shared/to_s'
require_relative 'shared/aliased_inspect'

describe "Method#to_s" do
  it_behaves_like :method_to_s, :to_s
  it_behaves_like :method_to_s_aliased, :to_s, -> meth { meth }
end
