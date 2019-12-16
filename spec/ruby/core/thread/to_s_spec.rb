require_relative '../../spec_helper'
require_relative 'shared/to_s'

describe "Thread#to_s" do
  ruby_version_is "2.5" do
    it_behaves_like :thread_to_s, :to_s
  end
end
