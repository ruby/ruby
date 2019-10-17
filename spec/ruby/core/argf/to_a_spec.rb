require_relative '../../spec_helper'
require_relative 'shared/readlines'

describe "ARGF.to_a" do
  it_behaves_like :argf_readlines, :to_a
end
