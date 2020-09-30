require_relative '../../spec_helper'
require_relative 'shared/key'

describe "ENV.index" do
  it_behaves_like :env_key, :index

  it "warns about deprecation" do
    -> do
      ENV.index("foo")
    end.should complain(/warning: ENV.index is deprecated; use ENV.key/)
  end
end
