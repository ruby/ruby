require_relative '../../spec_helper'
require_relative 'shared/image'

describe "Complex#imaginary" do
  it_behaves_like :complex_image, :imaginary
end
