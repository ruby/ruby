require_relative '../../spec_helper'
require_relative 'shared/trace'
require 'matrix'

describe "Matrix#trace" do
  it_behaves_like :trace, :trace
end
