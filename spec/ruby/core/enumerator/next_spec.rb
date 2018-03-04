require_relative '../../spec_helper'
require_relative '../../shared/enumerator/next'

describe "Enumerator#next" do
  it_behaves_like :enum_next,:next
end
