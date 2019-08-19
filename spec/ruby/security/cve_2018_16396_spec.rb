require_relative '../spec_helper'

describe "Array#pack" do

  it "resists CVE-2018-16396 by tainting output based on input" do
    "aAZBbHhuMmPp".each_char do |f|
      ["123456".taint].pack(f).tainted?.should be_true
    end
  end

end

describe "String#unpack" do

  it "resists CVE-2018-16396 by tainting output based on input" do
    "aAZBbHhuMm".each_char do |f|
      "123456".taint.unpack(f).first.tainted?.should be_true
    end
  end

end
