require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/difference'

describe "Array#-" do
  it_behaves_like :array_binary_difference, :-
end
