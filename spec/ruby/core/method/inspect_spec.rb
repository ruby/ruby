require_relative '../../spec_helper'
require_relative 'shared/to_s'

describe "Method#inspect" do
  it_behaves_like :method_to_s, :inspect
end
