require_relative '../../spec_helper'
require_relative 'shared/fileno'

describe "ARGF.to_i" do
  it_behaves_like :argf_fileno, :to_i
end
