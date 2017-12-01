require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../fixtures/classes', __FILE__)
require File.expand_path('../shared/unshift', __FILE__)

describe "Array#unshift" do
  it_behaves_like(:array_unshift, :unshift)
end
