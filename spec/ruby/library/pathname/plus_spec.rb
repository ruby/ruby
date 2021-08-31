require_relative '../../spec_helper'
require_relative 'shared/plus'

describe "Pathname#+" do
  it_behaves_like :pathname_plus, :+
end
