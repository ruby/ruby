require_relative '../../spec_helper'
require_relative 'shared/value'

describe "ENV.has_value?" do
  it_behaves_like :env_value, :has_value?
end
