require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../shared/identity', __FILE__)

describe "Matrix.I" do
  it_behaves_like :matrix_identity, :I
end
