require_relative '../../spec_helper'
require_relative 'shared/update'

describe "ENV.merge!" do
  it_behaves_like :env_update, :merge!
end
