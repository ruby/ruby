require_relative '../../spec_helper'
require_relative 'shared/begin'

describe "Range#begin" do
  it_behaves_like :range_begin, :begin
end
