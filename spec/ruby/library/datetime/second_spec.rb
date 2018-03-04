require_relative '../../spec_helper'
require_relative 'shared/sec'

describe "DateTime#second" do
  it_behaves_like :datetime_sec, :second
end
