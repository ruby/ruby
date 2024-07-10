require_relative '../../spec_helper'
require_relative '../../shared/time/yday'
require 'date'

describe "DateTime#yday" do
  it_behaves_like :time_yday, -> year, month, day { DateTime.new(year, month, day).yday }
end
