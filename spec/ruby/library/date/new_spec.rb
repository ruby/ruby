require 'date'
require_relative '../../spec_helper'
require_relative 'shared/civil'

describe "Date.new" do
  it_behaves_like :date_civil, :new
end
