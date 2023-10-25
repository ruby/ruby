require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'shared/identity'

  describe "Matrix.identity" do
    it_behaves_like :matrix_identity, :identity
  end
end
