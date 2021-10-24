require_relative '../../spec_helper'
require_relative 'shared/urandom'

describe "Random.urandom" do
  it_behaves_like :random_urandom, :urandom
end
