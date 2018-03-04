require_relative '../../spec_helper'
require_relative 'shared/each_codepoint'

describe "ARGF.each_codepoint" do
  it_behaves_like :argf_each_codepoint, :each_codepoint
end
