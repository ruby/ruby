require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/length'

describe "String#size" do
  it_behaves_like :string_length, :size
end
