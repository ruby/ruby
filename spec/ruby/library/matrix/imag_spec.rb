require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'shared/imaginary'

  describe "Matrix#imag" do
    it_behaves_like :matrix_imaginary, :imag
  end
end
