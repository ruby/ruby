require_relative '../../spec_helper'
require 'set'
require_relative 'shared/difference'

describe "Set#difference" do
  it_behaves_like :set_difference, :difference
end
