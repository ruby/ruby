require_relative '../../../spec_helper'
require_relative 'shared/select'

describe "Enumerator::Lazy#filter" do
  it_behaves_like :enumerator_lazy_select, :filter
end
