require_relative '../../spec_helper'
require_relative 'shared/each_byte'

describe "ARGF.bytes" do
  it_behaves_like :argf_each_byte, :bytes
end
