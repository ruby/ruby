require_relative '../../spec_helper'
require_relative 'shared/store'

describe "ENV.store" do
  it_behaves_like :env_store, :store
end
