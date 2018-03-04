require_relative '../../spec_helper'
require_relative '../../shared/enumerator/new'

describe "Enumerator.new" do
  it_behaves_like :enum_new, :new
end
