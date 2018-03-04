require_relative '../../spec_helper'
require_relative 'shared/each'

describe "ENV.each" do
  it_behaves_like :env_each, :each
end
