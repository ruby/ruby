require_relative "../../spec_helper"
require_relative 'shared/abs'

describe "Float#magnitude" do
  it_behaves_like :float_abs, :magnitude
end
