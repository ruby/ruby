require_relative '../../spec_helper'
require_relative 'shared/to_s'

describe "Proc#inspect" do
  it_behaves_like :proc_to_s, :inspect
end
