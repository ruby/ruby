require_relative '../../spec_helper'
require_relative 'shared/month'
require 'date'

describe "Date#month" do
  it_behaves_like :date_month, :month
end
