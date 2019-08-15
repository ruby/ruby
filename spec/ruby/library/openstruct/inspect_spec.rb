require_relative '../../spec_helper'
require 'ostruct'
require_relative 'fixtures/classes'
require_relative 'shared/inspect'

describe "OpenStruct#inspect" do
  it_behaves_like :ostruct_inspect, :inspect
end
