# -*- encoding: us-ascii -*-

require_relative '../../../spec_helper'
require_relative 'shared/collect_concat'

describe "Enumerator::Lazy#flat_map" do
  it_behaves_like :enumerator_lazy_collect_concat, :flat_map
end
