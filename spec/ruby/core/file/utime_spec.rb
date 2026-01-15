require_relative '../../spec_helper'
require_relative 'shared/update_time'

describe "File.utime" do
  it_behaves_like :update_time, :utime
end
