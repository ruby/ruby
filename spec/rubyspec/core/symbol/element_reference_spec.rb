require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../shared/slice.rb', __FILE__)

describe "Symbol#[]" do
  it_behaves_like(:symbol_slice, :[])
end
