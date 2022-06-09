require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'shared/identity'

  describe "Matrix.unit" do
    it_behaves_like :matrix_identity, :unit
  end
end
