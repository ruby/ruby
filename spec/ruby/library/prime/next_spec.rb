require_relative '../../spec_helper'
require_relative 'shared/next'
require 'prime'

describe "Prime#next" do
  it_behaves_like :prime_next, :next
end
