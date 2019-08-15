require_relative '../../spec_helper'
require_relative 'shared/sec'

describe "DateTime.sec" do
  it_behaves_like :datetime_sec, :sec
end
