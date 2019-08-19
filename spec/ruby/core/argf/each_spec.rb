require_relative '../../spec_helper'
require_relative 'shared/each_line'

describe "ARGF.each" do
  it_behaves_like :argf_each_line, :each
end
