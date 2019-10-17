require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/to_sym'

describe "String#intern" do
  it_behaves_like :string_to_sym, :intern
end
