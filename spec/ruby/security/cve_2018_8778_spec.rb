require_relative '../spec_helper'

describe "String#unpack" do
  it "resists CVE-2018-8778 by raising an exception when a position indicator is larger than a native integer" do
    pos = (1 << PlatformGuard::POINTER_SIZE) - 99
    -> {
      "0123456789".unpack("@#{pos}C10")
    }.should raise_error(RangeError, /pack length too big/)
  end
end
