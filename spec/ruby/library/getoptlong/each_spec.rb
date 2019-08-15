require_relative '../../spec_helper'
require 'getoptlong'
require_relative 'shared/each'

describe "GetoptLong#each" do
  it_behaves_like :getoptlong_each, :each
end
