require_relative '../../spec_helper'
require_relative 'shared/xmlschema'
require 'time'

describe "Time.xmlschema" do
  it_behaves_like :time_xmlschema, :iso8601
end
