require_relative '../../spec_helper'
require_relative 'shared/each_codepoint'

describe "ARGF.codepoints" do
  it_behaves_like :argf_each_codepoint, :codepoints
end
