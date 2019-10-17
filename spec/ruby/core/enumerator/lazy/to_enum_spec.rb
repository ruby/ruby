# -*- encoding: us-ascii -*-

require_relative '../../../spec_helper'
require_relative 'shared/to_enum'

describe "Enumerator::Lazy#to_enum" do
  it_behaves_like :enumerator_lazy_to_enum, :to_enum
end
