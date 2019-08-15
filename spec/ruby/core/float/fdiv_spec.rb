require_relative '../../spec_helper'
require_relative 'shared/quo'

describe "Float#fdiv" do
  it_behaves_like :float_quo, :fdiv
end
