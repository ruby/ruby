require_relative '../../spec_helper'
require_relative 'shared/include'

describe "ENV.member?" do
  it_behaves_like :env_include, :member?
end
