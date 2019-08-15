describe :array_pack_taint, shared: true do
  it "returns a tainted string when a pack argument is tainted" do
    ["abcd".taint, 0x20].pack(pack_format("3C")).tainted?.should be_true
  end

  it "does not return a tainted string when the array is tainted" do
    ["abcd", 0x20].taint.pack(pack_format("3C")).tainted?.should be_false
  end

  it "returns a tainted string when the format is tainted" do
    ["abcd", 0x20].pack(pack_format("3C").taint).tainted?.should be_true
  end

  it "returns a tainted string when an empty format is tainted" do
    ["abcd", 0x20].pack("".taint).tainted?.should be_true
  end

  it "returns a untrusted string when the format is untrusted" do
    ["abcd", 0x20].pack(pack_format("3C").untrust).untrusted?.should be_true
  end

  it "returns a untrusted string when the empty format is untrusted" do
    ["abcd", 0x20].pack("".untrust).untrusted?.should be_true
  end

  it "returns a untrusted string when a pack argument is untrusted" do
    ["abcd".untrust, 0x20].pack(pack_format("3C")).untrusted?.should be_true
  end

  it "returns a trusted string when the array is untrusted" do
    ["abcd", 0x20].untrust.pack(pack_format("3C")).untrusted?.should be_false
  end
end
