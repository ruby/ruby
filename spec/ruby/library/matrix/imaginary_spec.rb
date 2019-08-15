require_relative '../../spec_helper'
require_relative 'shared/imaginary'

describe "Matrix#imaginary" do
  it_behaves_like :matrix_imaginary, :imaginary
end
