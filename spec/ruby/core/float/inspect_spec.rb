require_relative '../../spec_helper'
require_relative 'shared/to_s'

describe "Float#inspect" do
  it_behaves_like :float_to_s, :inspect
end
