require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'shared/transpose'

  describe "Matrix#transpose" do
    it_behaves_like :matrix_transpose, :t
  end
end
