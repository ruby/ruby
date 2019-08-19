require_relative '../../spec_helper'
require_relative 'shared/each_byte'

describe "ARGF.each_byte" do
  it_behaves_like :argf_each_byte, :each_byte
end
