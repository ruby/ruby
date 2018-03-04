require_relative '../../spec_helper'
require_relative 'shared/dup'

describe "Proc#clone" do
  it_behaves_like :proc_dup, :clone
end
