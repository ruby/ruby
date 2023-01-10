require_relative '../../spec_helper'
require_relative 'shared/civil'
require 'date'

describe "Date.civil" do
  it_behaves_like :date_civil, :civil
end
