require_relative '../../spec_helper'
require_relative 'shared/union'

describe "Set#+" do
  it_behaves_like :set_union, :+
end
