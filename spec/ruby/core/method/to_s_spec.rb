require_relative '../../spec_helper'
require_relative 'shared/to_s'

describe "Method#to_s" do
  it_behaves_like :method_to_s, :to_s
end
