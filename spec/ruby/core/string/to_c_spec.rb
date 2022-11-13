require_relative '../../spec_helper'
require_relative '../../shared/kernel/complex'
require_relative 'fixtures/to_c'

describe "String#to_c" do
  it_behaves_like :kernel_complex, :to_c_method, StringSpecs
end

describe "String#to_c" do
  it "returns a complex number with 0 as the real part, 0 as the imaginary part for unrecognised Strings" do
    'ruby'.to_c.should == Complex(0, 0)
  end

  it "ignores trailing garbage" do
    '79+4iruby'.to_c.should == Complex(79, 4)
  end

  it "understands Float::INFINITY" do
    'Infinity'.to_c.should == Complex(0, 1)
    '-Infinity'.to_c.should == Complex(0, -1)
  end

  it "understands Float::NAN" do
    'NaN'.to_c.should == Complex(0, 0)
  end

  it "understands a sequence of _" do
    '7__9+4__0i'.to_c.should == Complex(79, 40)
  end

  it "allows null-byte" do
    "1-2i\0".to_c.should == Complex(1, -2)
    "1\0-2i".to_c.should == Complex(1, 0)
    "\01-2i".to_c.should == Complex(0, 0)
  end

  it "raises Encoding::CompatibilityError if String is in not ASCII-compatible encoding" do
    -> {
      '79+4i'.encode("UTF-16").to_c
    }.should raise_error(Encoding::CompatibilityError, "ASCII incompatible encoding: UTF-16")
  end
end
