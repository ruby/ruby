require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../shared/inspect', __FILE__)
require 'set'

describe "Set#inspect" do
  it_behaves_like :set_inspect, :inspect
end
