require_relative '../../spec_helper'
require_relative 'shared/each_char'

describe "ARGF.each_char" do
  it_behaves_like :argf_each_char, :each_char
end
