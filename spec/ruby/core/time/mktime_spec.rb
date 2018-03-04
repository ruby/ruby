require_relative '../../spec_helper'
require_relative 'shared/local'
require_relative 'shared/time_params'

describe "Time.mktime" do
  it_behaves_like :time_local, :mktime
  it_behaves_like :time_local_10_arg, :mktime
  it_behaves_like :time_params, :mktime
  it_behaves_like :time_params_10_arg, :mktime
  it_behaves_like :time_params_microseconds, :mktime
end
