require_relative '../../../spec_helper'
require_relative 'shared/select'

ruby_version_is "2.6" do
  describe "Enumerator::Lazy#filter" do
    it_behaves_like :enumerator_lazy_select, :filter
  end
end
