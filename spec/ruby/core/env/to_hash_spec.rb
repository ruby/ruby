require_relative 'spec_helper'
require_relative 'shared/to_hash'

describe "ENV.to_hash" do
  it_behaves_like :env_to_hash, :to_hash
end
