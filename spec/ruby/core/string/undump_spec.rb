# encoding: utf-8
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is '2.5' do
  describe "String#undump" do
    it "taints the result if self is tainted" do
      '"foo"'.taint.undump.tainted?.should == true
    end

    it "untrusts the result if self is untrusted" do
      '"foo"'.untrust.undump.untrusted?.should == true
    end

    it "does not take into account if a string is frozen" do
      '"foo"'.freeze.undump.frozen?.should == false
    end

    it "always returns String instance" do
      StringSpecs::MyString.new('"foo"').undump.should be_an_instance_of(String)
    end

    it "strips outer \"" do
      '"foo"'.undump.should == 'foo'
    end

    it "returns a string with special characters in \\<char> notation replaced with the characters" do
      [ ['"\\a"', "\a"],
        ['"\\b"', "\b"],
        ['"\\t"', "\t"],
        ['"\\n"', "\n"],
        ['"\\v"', "\v"],
        ['"\\f"', "\f"],
        ['"\\r"', "\r"],
        ['"\\e"', "\e"]
      ].should be_computed_by(:undump)
    end

    it "returns a string with unescaped sequencies \" and \\" do
      [ ['"\\""' , "\""],
        ['"\\\\"', "\\"]
      ].should be_computed_by(:undump)
    end

    it "returns a string with unescaped sequences \\#<char> when # is followed by $, @, {" do
      [ ['"\\#$PATH"', "\#$PATH"],
        ['"\\#@a"',    "\#@a"],
        ['"\\#@@a"',   "\#@@a"],
        ['"\\#{a}"',   "\#{a}"]
      ].should be_computed_by(:undump)
    end

    it "returns a string with # not escaped when followed by any other character" do
      [ ['"#"', '#'],
        ['"#1"', '#1']
      ].should be_computed_by(:undump)
    end

    it "returns a string with printable non-alphanumeric characters" do
      [ ['" "', ' '],
        ['"!"', '!'],
        ['"$"', '$'],
        ['"%"', '%'],
        ['"&"', '&'],
        ['"\'"', '\''],
        ['"("', '('],
        ['")"', ')'],
        ['"*"', '*'],
        ['"+"', '+'],
        ['","', ','],
        ['"-"', '-'],
        ['"."', '.'],
        ['"/"', '/'],
        ['":"', ':'],
        ['";"', ';'],
        ['"<"', '<'],
        ['"="', '='],
        ['">"', '>'],
        ['"?"', '?'],
        ['"@"', '@'],
        ['"["', '['],
        ['"]"', ']'],
        ['"^"', '^'],
        ['"_"', '_'],
        ['"`"', '`'],
        ['"{"', '{'],
        ['"|"', '|'],
        ['"}"', '}'],
        ['"~"', '~']
      ].should be_computed_by(:undump)
    end

    it "returns a string with numeric characters unescaped" do
      [ ['"0"', "0"],
        ['"1"', "1"],
        ['"2"', "2"],
        ['"3"', "3"],
        ['"4"', "4"],
        ['"5"', "5"],
        ['"6"', "6"],
        ['"7"', "7"],
        ['"8"', "8"],
        ['"9"', "9"],
      ].should be_computed_by(:undump)
    end

    it "returns a string with upper-case alpha characters unescaped" do
      [ ['"A"', 'A'],
        ['"B"', 'B'],
        ['"C"', 'C'],
        ['"D"', 'D'],
        ['"E"', 'E'],
        ['"F"', 'F'],
        ['"G"', 'G'],
        ['"H"', 'H'],
        ['"I"', 'I'],
        ['"J"', 'J'],
        ['"K"', 'K'],
        ['"L"', 'L'],
        ['"M"', 'M'],
        ['"N"', 'N'],
        ['"O"', 'O'],
        ['"P"', 'P'],
        ['"Q"', 'Q'],
        ['"R"', 'R'],
        ['"S"', 'S'],
        ['"T"', 'T'],
        ['"U"', 'U'],
        ['"V"', 'V'],
        ['"W"', 'W'],
        ['"X"', 'X'],
        ['"Y"', 'Y'],
        ['"Z"', 'Z']
      ].should be_computed_by(:undump)
    end

    it "returns a string with lower-case alpha characters unescaped" do
      [ ['"a"', 'a'],
        ['"b"', 'b'],
        ['"c"', 'c'],
        ['"d"', 'd'],
        ['"e"', 'e'],
        ['"f"', 'f'],
        ['"g"', 'g'],
        ['"h"', 'h'],
        ['"i"', 'i'],
        ['"j"', 'j'],
        ['"k"', 'k'],
        ['"l"', 'l'],
        ['"m"', 'm'],
        ['"n"', 'n'],
        ['"o"', 'o'],
        ['"p"', 'p'],
        ['"q"', 'q'],
        ['"r"', 'r'],
        ['"s"', 's'],
        ['"t"', 't'],
        ['"u"', 'u'],
        ['"v"', 'v'],
        ['"w"', 'w'],
        ['"x"', 'x'],
        ['"y"', 'y'],
        ['"z"', 'z']
      ].should be_computed_by(:undump)
    end

    it "returns a string with \\x notation replaced with non-printing ASCII character" do
      [ ['"\\x00"', 0000.chr.force_encoding('utf-8')],
        ['"\\x01"', 0001.chr.force_encoding('utf-8')],
        ['"\\x02"', 0002.chr.force_encoding('utf-8')],
        ['"\\x03"', 0003.chr.force_encoding('utf-8')],
        ['"\\x04"', 0004.chr.force_encoding('utf-8')],
        ['"\\x05"', 0005.chr.force_encoding('utf-8')],
        ['"\\x06"', 0006.chr.force_encoding('utf-8')],
        ['"\\x0E"', 0016.chr.force_encoding('utf-8')],
        ['"\\x0F"', 0017.chr.force_encoding('utf-8')],
        ['"\\x10"', 0020.chr.force_encoding('utf-8')],
        ['"\\x11"', 0021.chr.force_encoding('utf-8')],
        ['"\\x12"', 0022.chr.force_encoding('utf-8')],
        ['"\\x13"', 0023.chr.force_encoding('utf-8')],
        ['"\\x14"', 0024.chr.force_encoding('utf-8')],
        ['"\\x15"', 0025.chr.force_encoding('utf-8')],
        ['"\\x16"', 0026.chr.force_encoding('utf-8')],
        ['"\\x17"', 0027.chr.force_encoding('utf-8')],
        ['"\\x18"', 0030.chr.force_encoding('utf-8')],
        ['"\\x19"', 0031.chr.force_encoding('utf-8')],
        ['"\\x1A"', 0032.chr.force_encoding('utf-8')],
        ['"\\x1C"', 0034.chr.force_encoding('utf-8')],
        ['"\\x1D"', 0035.chr.force_encoding('utf-8')],
        ['"\\x1E"', 0036.chr.force_encoding('utf-8')],
        ['"\\x1F"', 0037.chr.force_encoding('utf-8')],
        ['"\\x7F"', 0177.chr.force_encoding('utf-8')],
        ['"\\x80"', 0200.chr.force_encoding('utf-8')],
        ['"\\x81"', 0201.chr.force_encoding('utf-8')],
        ['"\\x82"', 0202.chr.force_encoding('utf-8')],
        ['"\\x83"', 0203.chr.force_encoding('utf-8')],
        ['"\\x84"', 0204.chr.force_encoding('utf-8')],
        ['"\\x85"', 0205.chr.force_encoding('utf-8')],
        ['"\\x86"', 0206.chr.force_encoding('utf-8')],
        ['"\\x87"', 0207.chr.force_encoding('utf-8')],
        ['"\\x88"', 0210.chr.force_encoding('utf-8')],
        ['"\\x89"', 0211.chr.force_encoding('utf-8')],
        ['"\\x8A"', 0212.chr.force_encoding('utf-8')],
        ['"\\x8B"', 0213.chr.force_encoding('utf-8')],
        ['"\\x8C"', 0214.chr.force_encoding('utf-8')],
        ['"\\x8D"', 0215.chr.force_encoding('utf-8')],
        ['"\\x8E"', 0216.chr.force_encoding('utf-8')],
        ['"\\x8F"', 0217.chr.force_encoding('utf-8')],
        ['"\\x90"', 0220.chr.force_encoding('utf-8')],
        ['"\\x91"', 0221.chr.force_encoding('utf-8')],
        ['"\\x92"', 0222.chr.force_encoding('utf-8')],
        ['"\\x93"', 0223.chr.force_encoding('utf-8')],
        ['"\\x94"', 0224.chr.force_encoding('utf-8')],
        ['"\\x95"', 0225.chr.force_encoding('utf-8')],
        ['"\\x96"', 0226.chr.force_encoding('utf-8')],
        ['"\\x97"', 0227.chr.force_encoding('utf-8')],
        ['"\\x98"', 0230.chr.force_encoding('utf-8')],
        ['"\\x99"', 0231.chr.force_encoding('utf-8')],
        ['"\\x9A"', 0232.chr.force_encoding('utf-8')],
        ['"\\x9B"', 0233.chr.force_encoding('utf-8')],
        ['"\\x9C"', 0234.chr.force_encoding('utf-8')],
        ['"\\x9D"', 0235.chr.force_encoding('utf-8')],
        ['"\\x9E"', 0236.chr.force_encoding('utf-8')],
        ['"\\x9F"', 0237.chr.force_encoding('utf-8')],
        ['"\\xA0"', 0240.chr.force_encoding('utf-8')],
        ['"\\xA1"', 0241.chr.force_encoding('utf-8')],
        ['"\\xA2"', 0242.chr.force_encoding('utf-8')],
        ['"\\xA3"', 0243.chr.force_encoding('utf-8')],
        ['"\\xA4"', 0244.chr.force_encoding('utf-8')],
        ['"\\xA5"', 0245.chr.force_encoding('utf-8')],
        ['"\\xA6"', 0246.chr.force_encoding('utf-8')],
        ['"\\xA7"', 0247.chr.force_encoding('utf-8')],
        ['"\\xA8"', 0250.chr.force_encoding('utf-8')],
        ['"\\xA9"', 0251.chr.force_encoding('utf-8')],
        ['"\\xAA"', 0252.chr.force_encoding('utf-8')],
        ['"\\xAB"', 0253.chr.force_encoding('utf-8')],
        ['"\\xAC"', 0254.chr.force_encoding('utf-8')],
        ['"\\xAD"', 0255.chr.force_encoding('utf-8')],
        ['"\\xAE"', 0256.chr.force_encoding('utf-8')],
        ['"\\xAF"', 0257.chr.force_encoding('utf-8')],
        ['"\\xB0"', 0260.chr.force_encoding('utf-8')],
        ['"\\xB1"', 0261.chr.force_encoding('utf-8')],
        ['"\\xB2"', 0262.chr.force_encoding('utf-8')],
        ['"\\xB3"', 0263.chr.force_encoding('utf-8')],
        ['"\\xB4"', 0264.chr.force_encoding('utf-8')],
        ['"\\xB5"', 0265.chr.force_encoding('utf-8')],
        ['"\\xB6"', 0266.chr.force_encoding('utf-8')],
        ['"\\xB7"', 0267.chr.force_encoding('utf-8')],
        ['"\\xB8"', 0270.chr.force_encoding('utf-8')],
        ['"\\xB9"', 0271.chr.force_encoding('utf-8')],
        ['"\\xBA"', 0272.chr.force_encoding('utf-8')],
        ['"\\xBB"', 0273.chr.force_encoding('utf-8')],
        ['"\\xBC"', 0274.chr.force_encoding('utf-8')],
        ['"\\xBD"', 0275.chr.force_encoding('utf-8')],
        ['"\\xBE"', 0276.chr.force_encoding('utf-8')],
        ['"\\xBF"', 0277.chr.force_encoding('utf-8')],
        ['"\\xC0"', 0300.chr.force_encoding('utf-8')],
        ['"\\xC1"', 0301.chr.force_encoding('utf-8')],
        ['"\\xC2"', 0302.chr.force_encoding('utf-8')],
        ['"\\xC3"', 0303.chr.force_encoding('utf-8')],
        ['"\\xC4"', 0304.chr.force_encoding('utf-8')],
        ['"\\xC5"', 0305.chr.force_encoding('utf-8')],
        ['"\\xC6"', 0306.chr.force_encoding('utf-8')],
        ['"\\xC7"', 0307.chr.force_encoding('utf-8')],
        ['"\\xC8"', 0310.chr.force_encoding('utf-8')],
        ['"\\xC9"', 0311.chr.force_encoding('utf-8')],
        ['"\\xCA"', 0312.chr.force_encoding('utf-8')],
        ['"\\xCB"', 0313.chr.force_encoding('utf-8')],
        ['"\\xCC"', 0314.chr.force_encoding('utf-8')],
        ['"\\xCD"', 0315.chr.force_encoding('utf-8')],
        ['"\\xCE"', 0316.chr.force_encoding('utf-8')],
        ['"\\xCF"', 0317.chr.force_encoding('utf-8')],
        ['"\\xD0"', 0320.chr.force_encoding('utf-8')],
        ['"\\xD1"', 0321.chr.force_encoding('utf-8')],
        ['"\\xD2"', 0322.chr.force_encoding('utf-8')],
        ['"\\xD3"', 0323.chr.force_encoding('utf-8')],
        ['"\\xD4"', 0324.chr.force_encoding('utf-8')],
        ['"\\xD5"', 0325.chr.force_encoding('utf-8')],
        ['"\\xD6"', 0326.chr.force_encoding('utf-8')],
        ['"\\xD7"', 0327.chr.force_encoding('utf-8')],
        ['"\\xD8"', 0330.chr.force_encoding('utf-8')],
        ['"\\xD9"', 0331.chr.force_encoding('utf-8')],
        ['"\\xDA"', 0332.chr.force_encoding('utf-8')],
        ['"\\xDB"', 0333.chr.force_encoding('utf-8')],
        ['"\\xDC"', 0334.chr.force_encoding('utf-8')],
        ['"\\xDD"', 0335.chr.force_encoding('utf-8')],
        ['"\\xDE"', 0336.chr.force_encoding('utf-8')],
        ['"\\xDF"', 0337.chr.force_encoding('utf-8')],
        ['"\\xE0"', 0340.chr.force_encoding('utf-8')],
        ['"\\xE1"', 0341.chr.force_encoding('utf-8')],
        ['"\\xE2"', 0342.chr.force_encoding('utf-8')],
        ['"\\xE3"', 0343.chr.force_encoding('utf-8')],
        ['"\\xE4"', 0344.chr.force_encoding('utf-8')],
        ['"\\xE5"', 0345.chr.force_encoding('utf-8')],
        ['"\\xE6"', 0346.chr.force_encoding('utf-8')],
        ['"\\xE7"', 0347.chr.force_encoding('utf-8')],
        ['"\\xE8"', 0350.chr.force_encoding('utf-8')],
        ['"\\xE9"', 0351.chr.force_encoding('utf-8')],
        ['"\\xEA"', 0352.chr.force_encoding('utf-8')],
        ['"\\xEB"', 0353.chr.force_encoding('utf-8')],
        ['"\\xEC"', 0354.chr.force_encoding('utf-8')],
        ['"\\xED"', 0355.chr.force_encoding('utf-8')],
        ['"\\xEE"', 0356.chr.force_encoding('utf-8')],
        ['"\\xEF"', 0357.chr.force_encoding('utf-8')],
        ['"\\xF0"', 0360.chr.force_encoding('utf-8')],
        ['"\\xF1"', 0361.chr.force_encoding('utf-8')],
        ['"\\xF2"', 0362.chr.force_encoding('utf-8')],
        ['"\\xF3"', 0363.chr.force_encoding('utf-8')],
        ['"\\xF4"', 0364.chr.force_encoding('utf-8')],
        ['"\\xF5"', 0365.chr.force_encoding('utf-8')],
        ['"\\xF6"', 0366.chr.force_encoding('utf-8')],
        ['"\\xF7"', 0367.chr.force_encoding('utf-8')],
        ['"\\xF8"', 0370.chr.force_encoding('utf-8')],
        ['"\\xF9"', 0371.chr.force_encoding('utf-8')],
        ['"\\xFA"', 0372.chr.force_encoding('utf-8')],
        ['"\\xFB"', 0373.chr.force_encoding('utf-8')],
        ['"\\xFC"', 0374.chr.force_encoding('utf-8')],
        ['"\\xFD"', 0375.chr.force_encoding('utf-8')],
        ['"\\xFE"', 0376.chr.force_encoding('utf-8')],
        ['"\\xFF"', 0377.chr.force_encoding('utf-8')]
      ].should be_computed_by(:undump)
    end

    it "returns a string with \\u{} notation replaced with multi-byte UTF-8 characters" do
      [ ['"\u{80}"', 0200.chr('utf-8')],
        ['"\u{81}"', 0201.chr('utf-8')],
        ['"\u{82}"', 0202.chr('utf-8')],
        ['"\u{83}"', 0203.chr('utf-8')],
        ['"\u{84}"', 0204.chr('utf-8')],
        ['"\u{86}"', 0206.chr('utf-8')],
        ['"\u{87}"', 0207.chr('utf-8')],
        ['"\u{88}"', 0210.chr('utf-8')],
        ['"\u{89}"', 0211.chr('utf-8')],
        ['"\u{8a}"', 0212.chr('utf-8')],
        ['"\u{8b}"', 0213.chr('utf-8')],
        ['"\u{8c}"', 0214.chr('utf-8')],
        ['"\u{8d}"', 0215.chr('utf-8')],
        ['"\u{8e}"', 0216.chr('utf-8')],
        ['"\u{8f}"', 0217.chr('utf-8')],
        ['"\u{90}"', 0220.chr('utf-8')],
        ['"\u{91}"', 0221.chr('utf-8')],
        ['"\u{92}"', 0222.chr('utf-8')],
        ['"\u{93}"', 0223.chr('utf-8')],
        ['"\u{94}"', 0224.chr('utf-8')],
        ['"\u{95}"', 0225.chr('utf-8')],
        ['"\u{96}"', 0226.chr('utf-8')],
        ['"\u{97}"', 0227.chr('utf-8')],
        ['"\u{98}"', 0230.chr('utf-8')],
        ['"\u{99}"', 0231.chr('utf-8')],
        ['"\u{9a}"', 0232.chr('utf-8')],
        ['"\u{9b}"', 0233.chr('utf-8')],
        ['"\u{9c}"', 0234.chr('utf-8')],
        ['"\u{9d}"', 0235.chr('utf-8')],
        ['"\u{9e}"', 0236.chr('utf-8')],
        ['"\u{9f}"', 0237.chr('utf-8')],
      ].should be_computed_by(:undump)
    end

    it "returns a string with \\uXXXX notation replaced with multi-byte UTF-8 characters" do
      [ ['"\u0080"', 0200.chr('utf-8')],
        ['"\u0081"', 0201.chr('utf-8')],
        ['"\u0082"', 0202.chr('utf-8')],
        ['"\u0083"', 0203.chr('utf-8')],
        ['"\u0084"', 0204.chr('utf-8')],
        ['"\u0086"', 0206.chr('utf-8')],
        ['"\u0087"', 0207.chr('utf-8')],
        ['"\u0088"', 0210.chr('utf-8')],
        ['"\u0089"', 0211.chr('utf-8')],
        ['"\u008a"', 0212.chr('utf-8')],
        ['"\u008b"', 0213.chr('utf-8')],
        ['"\u008c"', 0214.chr('utf-8')],
        ['"\u008d"', 0215.chr('utf-8')],
        ['"\u008e"', 0216.chr('utf-8')],
        ['"\u008f"', 0217.chr('utf-8')],
        ['"\u0090"', 0220.chr('utf-8')],
        ['"\u0091"', 0221.chr('utf-8')],
        ['"\u0092"', 0222.chr('utf-8')],
        ['"\u0093"', 0223.chr('utf-8')],
        ['"\u0094"', 0224.chr('utf-8')],
        ['"\u0095"', 0225.chr('utf-8')],
        ['"\u0096"', 0226.chr('utf-8')],
        ['"\u0097"', 0227.chr('utf-8')],
        ['"\u0098"', 0230.chr('utf-8')],
        ['"\u0099"', 0231.chr('utf-8')],
        ['"\u009a"', 0232.chr('utf-8')],
        ['"\u009b"', 0233.chr('utf-8')],
        ['"\u009c"', 0234.chr('utf-8')],
        ['"\u009d"', 0235.chr('utf-8')],
        ['"\u009e"', 0236.chr('utf-8')],
        ['"\u009f"', 0237.chr('utf-8')],
      ].should be_computed_by(:undump)
    end

    it "undumps correctly string produced from non ASCII-compatible one" do
      s = "\u{876}".encode('utf-16be')
      s.dump.undump.should == s

      '"\\bv".force_encoding("UTF-16BE")'.undump.should == "\u0876".encode('utf-16be')
    end

    it "keeps origin encoding" do
      '"foo"'.encode("ISO-8859-1").undump.encoding.should == Encoding::ISO_8859_1
      '"foo"'.encode('windows-1251').undump.encoding.should == Encoding::Windows_1251
    end

    describe "Limitations" do
      it "cannot undump non ASCII-compatible string" do
        -> { '"foo"'.encode('utf-16le').undump }.should raise_error(Encoding::CompatibilityError)
      end
    end

    describe "invalid dump" do
      it "raises RuntimeError exception if wrapping \" are missing" do
        -> { 'foo'.undump }.should raise_error(RuntimeError, /invalid dumped string/)
        -> { '"foo'.undump }.should raise_error(RuntimeError, /unterminated dumped string/)
        -> { 'foo"'.undump }.should raise_error(RuntimeError, /invalid dumped string/)
        -> { "'foo'".undump }.should raise_error(RuntimeError, /invalid dumped string/)
      end

      it "raises RuntimeError if there is incorrect \\x sequence" do
        -> { '"\x"'.undump }.should raise_error(RuntimeError, /invalid hex escape/)
        -> { '"\\x3y"'.undump }.should raise_error(RuntimeError, /invalid hex escape/)
      end

      it "raises RuntimeError in there is incorrect \\u sequence" do
        -> { '"\\u"'.undump }.should raise_error(RuntimeError, /invalid Unicode escape/)
        -> { '"\\u{"'.undump }.should raise_error(RuntimeError, /invalid Unicode escape/)
        -> { '"\\u{3042"'.undump }.should raise_error(RuntimeError, /invalid Unicode escape/)
        -> { '"\\u"'.undump }.should raise_error(RuntimeError, /invalid Unicode escape/)
      end

      it "raises RuntimeError if there is malformed dump of non ASCII-compatible string" do
        -> { '"".force_encoding("BINARY"'.undump }.should raise_error(RuntimeError, /invalid dumped string/)
        -> { '"".force_encoding("Unknown")'.undump }.should raise_error(RuntimeError, /dumped string has unknown encoding name/)
        -> { '"".force_encoding()'.undump }.should raise_error(RuntimeError, /invalid dumped string/)
      end

      it "raises RuntimeError if string contains \0 character" do
        -> { "\"foo\0\"".undump }.should raise_error(RuntimeError, /string contains null byte/)
      end

      it "raises RuntimeError if string contains non ASCII character" do
        -> { "\"\u3042\"".undump }.should raise_error(RuntimeError, /non-ASCII character detected/)
      end

      it "raises RuntimeError if there are some excessive \"" do
        -> { '" "" "'.undump }.should raise_error(RuntimeError, /invalid dumped string/)
      end
    end
  end
end
