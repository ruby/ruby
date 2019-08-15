require_relative '../../spec_helper'
require_relative 'shared/load'

describe "Marshal.load" do
  it_behaves_like :marshal_load, :load
end
