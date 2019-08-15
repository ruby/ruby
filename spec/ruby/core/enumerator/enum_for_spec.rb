require_relative '../../spec_helper'
require_relative '../../shared/enumerator/enum_for'

describe "Enumerator#enum_for" do
  it_behaves_like :enum_for, :enum_for
end
