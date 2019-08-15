# -*- encoding: binary -*-
require_relative '../../spec_helper'
require_relative 'shared/urandom'

ruby_version_is "2.5" do
  describe "Random.urandom" do
    it_behaves_like :random_urandom, :urandom
  end
end
