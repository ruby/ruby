require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'shared/rectangular'

  describe "Matrix#rectangular" do
    it_behaves_like :matrix_rectangular, :rectangular
  end
end
