require_relative '../../spec_helper'
require_relative 'shared/image'

describe "Complex#imag" do
  it_behaves_like :complex_image, :imag
end
