# -*- encoding: us-ascii -*-

require_relative '../../../spec_helper'
require_relative 'shared/select'

describe "Enumerator::Lazy#find_all" do
  it_behaves_like :enumerator_lazy_select, :find_all
end
