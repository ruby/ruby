require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/exponent'

describe "Integer#**" do
  it_behaves_like :integer_exponent, :**
end
