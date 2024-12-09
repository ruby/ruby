require_relative '../../spec_helper'
require_relative 'shared/xmlschema'
require 'time'

describe "Time.iso8601" do
  it_behaves_like :time_library_xmlschema, :iso8601
end
