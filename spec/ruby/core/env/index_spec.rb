require_relative '../../spec_helper'
require_relative 'shared/key'

describe "ENV.index" do
  it_behaves_like :env_key, :index

  before :each do
    if Warning.respond_to?(:[])
      @deprecated = Warning[:deprecated]
      Warning[:deprecated] = true
    end
  end

  after :each do
    if Warning.respond_to?(:[])
      Warning[:deprecated] = @deprecated
    end
  end

  it "warns about deprecation" do
    -> do
      ENV.index("foo")
    end.should complain(/warning: ENV.index is deprecated; use ENV.key/)
  end
end
