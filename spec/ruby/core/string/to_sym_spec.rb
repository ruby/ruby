require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/to_sym'

describe "String#to_sym" do
  it_behaves_like :string_to_sym, :to_sym
end
