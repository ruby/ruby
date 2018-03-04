require_relative '../../spec_helper'
require_relative 'shared/each_line'

describe "ARGF.lines" do
  it_behaves_like :argf_each_line, :lines
end
