require_relative '../../spec_helper'
require_relative 'shared/readlines'

describe "ARGF.readlines" do
  it_behaves_like :argf_readlines, :readlines
end
