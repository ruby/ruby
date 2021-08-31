require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'shared/collect'

  describe "Matrix#map" do
    it_behaves_like :collect, :map
  end
end
