require_relative '../../spec_helper'
require_relative 'shared/quo'

describe "Float#quo" do
  it_behaves_like :float_quo, :quo
end
