require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

RSpec.describe Object, "#bignum_value" do
  it "returns a value that is an instance of Bignum on any platform" do
    expect(bignum_value).to be > fixnum_max
  end

  it "returns the default value incremented by the argument" do
    expect(bignum_value(42)).to eq(bignum_value + 42)
  end
end

RSpec.describe Object, "-bignum_value" do
  it "returns a value that is an instance of Bignum on any platform" do
    expect(-bignum_value).to be < fixnum_min
  end
end

RSpec.describe Object, "#nan_value" do
  it "returns NaN" do
    expect(nan_value.nan?).to be_truthy
  end
end

RSpec.describe Object, "#infinity_value" do
  it "returns Infinity" do
    expect(infinity_value.infinite?).to eq(1)
  end
end
