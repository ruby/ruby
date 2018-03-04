require_relative '../../spec_helper'
require_relative 'shared/include'

describe "ENV.include?" do
  it_behaves_like :env_include, :include?
end
