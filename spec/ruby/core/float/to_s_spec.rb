require_relative '../../spec_helper'
require_relative 'shared/to_s'

describe "Float#to_s" do
  it_behaves_like :float_to_s, :to_s
end
