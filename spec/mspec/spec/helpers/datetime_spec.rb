require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

RSpec.describe Object, "#new_datetime" do
  it "returns a default DateTime instance" do
    expect(new_datetime).to eq(DateTime.new)
  end

  it "returns a DateTime instance with the specified year value" do
    d = new_datetime :year => 1970
    expect(d.year).to eq(1970)
  end

  it "returns a DateTime instance with the specified month value" do
    d = new_datetime :month => 11
    expect(d.mon).to eq(11)
  end

  it "returns a DateTime instance with the specified day value" do
    d = new_datetime :day => 23
    expect(d.day).to eq(23)
  end

  it "returns a DateTime instance with the specified hour value" do
    d = new_datetime :hour => 10
    expect(d.hour).to eq(10)
  end

  it "returns a DateTime instance with the specified minute value" do
    d = new_datetime :minute => 10
    expect(d.min).to eq(10)
  end

  it "returns a DateTime instance with the specified second value" do
    d = new_datetime :second => 2
    expect(d.sec).to eq(2)
  end

  it "returns a DateTime instance with the specified offset value" do
    d = new_datetime :offset => Rational(3,24)
    expect(d.offset).to eq(Rational(3,24))
  end
end
