require_relative '../../spec_helper'
require_relative 'shared/update'

describe "ENV.update" do
  it_behaves_like :env_update, :update
end
