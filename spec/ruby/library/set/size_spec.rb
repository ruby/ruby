require_relative '../../spec_helper'
require_relative 'shared/length'
require 'set'

describe "Set#size" do
  it_behaves_like :set_length, :size
end
