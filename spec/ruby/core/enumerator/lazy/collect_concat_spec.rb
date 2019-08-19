# -*- encoding: us-ascii -*-

require_relative '../../../spec_helper'
require_relative 'shared/collect_concat'

describe "Enumerator::Lazy#collect_concat" do
  it_behaves_like :enumerator_lazy_collect_concat, :collect_concat
end
