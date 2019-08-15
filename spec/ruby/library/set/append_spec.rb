require_relative '../../spec_helper'
require 'set'
require_relative 'shared/add'

describe "Set#<<" do
  it_behaves_like :set_add, :<<
end
