require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'shared/new'

describe "Exception.new" do
  it_behaves_like :exception_new, :new
end
