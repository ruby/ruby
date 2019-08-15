require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/string/times'

describe "String#*" do
  it_behaves_like :string_times, :*, -> str, times { str * times }
end
