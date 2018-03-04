require_relative '../../spec_helper'
require 'date'

describe "DateTime#to_s" do
  it "returns a new String object" do
    dt = DateTime.new(2012, 12, 24, 1, 2, 3, "+03:00")
    dt.to_s.should be_kind_of(String)
  end

  it "maintains timezone regardless of local time" do
    dt = DateTime.new(2012, 12, 24, 1, 2, 3, "+03:00")

    with_timezone("Pactific/Pago_Pago", -11) do
      dt.to_s.should == "2012-12-24T01:02:03+03:00"
    end
  end
end
