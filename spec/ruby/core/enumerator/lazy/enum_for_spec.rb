# -*- encoding: us-ascii -*-

require_relative '../../../spec_helper'
require_relative 'shared/to_enum'

describe "Enumerator::Lazy#enum_for" do
  it_behaves_like :enumerator_lazy_to_enum, :enum_for
end
