require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'shared/conjugate'

  describe "Matrix#conjugate" do
    it_behaves_like :matrix_conjugate, :conjugate
  end
end
