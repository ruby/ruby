require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/dup'

describe "Struct-based class#clone" do
  it_behaves_like :struct_dup, :clone
end
