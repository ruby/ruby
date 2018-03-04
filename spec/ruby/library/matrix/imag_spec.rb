require_relative '../../spec_helper'
require_relative 'shared/imaginary'

describe "Matrix#imag" do
  it_behaves_like :matrix_imaginary, :imag
end
