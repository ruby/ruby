require_relative '../../spec_helper'
require_relative 'shared/trace'
require 'matrix'

describe "Matrix#tr" do
  it_behaves_like :trace, :tr
end
