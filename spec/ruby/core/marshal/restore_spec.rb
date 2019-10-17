require_relative '../../spec_helper'
require_relative 'shared/load'

describe "Marshal.restore" do
  it_behaves_like :marshal_load, :restore
end
