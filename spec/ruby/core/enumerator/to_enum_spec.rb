require_relative '../../spec_helper'
require_relative 'shared/enum_for'

describe "Enumerator#to_enum" do
  it_behaves_like :enum_for, :to_enum
end
