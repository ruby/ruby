require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../fixtures/classes', __FILE__)
require File.expand_path('../shared/collect', __FILE__)

describe "Enumerable#collect" do
  it_behaves_like :enumerable_collect , :collect
end
