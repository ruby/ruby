require_relative '../../spec_helper'
require_relative 'shared/key'

describe "ENV.index" do
  it_behaves_like :env_key, :index
end
