require_relative '../../spec_helper'
require_relative 'shared/each_line'

describe "ARGF.each_line" do
  it_behaves_like :argf_each_line, :each_line
end
