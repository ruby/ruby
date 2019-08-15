require_relative '../../spec_helper'
require_relative '../enumerable/shared/enumeratorized'
require_relative 'shared/select'

ruby_version_is "2.6" do
  describe "ENV.filter!" do
    it_behaves_like :env_select!, :filter!
    it_behaves_like :enumeratorized_with_origin_size, :filter!, ENV
  end

  describe "ENV.filter" do
    it_behaves_like :env_select, :filter
    it_behaves_like :enumeratorized_with_origin_size, :filter, ENV
  end
end
