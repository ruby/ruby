require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'shared/determinant'
  require 'matrix'

  describe "Matrix#determinant" do
    it_behaves_like :determinant, :determinant
  end
end
