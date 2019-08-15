# -*- encoding: us-ascii -*-

require_relative '../../../spec_helper'
require_relative 'shared/collect'

describe "Enumerator::Lazy#collect" do
  it_behaves_like :enumerator_lazy_collect, :collect
end
