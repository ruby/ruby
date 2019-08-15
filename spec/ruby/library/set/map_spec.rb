require_relative '../../spec_helper'
require 'set'
require_relative 'shared/collect'

describe "Set#map!" do
  it_behaves_like :set_collect_bang, :map!
end
