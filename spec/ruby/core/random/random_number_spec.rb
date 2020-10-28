require_relative '../../spec_helper'
require_relative 'shared/rand'

describe "Random.random_number" do
  it_behaves_like :random_number, :random_number, Random.new

  ruby_version_is "2.6" do
    it_behaves_like :random_number, :random_number, Random
  end
end
