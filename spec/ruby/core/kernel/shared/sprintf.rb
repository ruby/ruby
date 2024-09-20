describe :kernel_sprintf, shared: true do
  describe "integer formats" do
    it "converts argument into Integer with to_int" do
      obj = Object.new
      def obj.to_i; 10; end
      def obj.to_int; 10; end

      obj.should_receive(:to_int).and_return(10)
      @method.call("%b", obj).should == "1010"
    end

    it "converts argument into Integer with to_i if to_int isn't available" do
      obj = Object.new
      def obj.to_i; 10; end

      obj.should_receive(:to_i).and_return(10)
      @method.call("%b", obj).should == "1010"
    end

    it "converts String argument with Kernel#Integer" do
      @method.call("%d", "0b1010").should == "10"
      @method.call("%d", "112").should == "112"
      @method.call("%d", "0127").should == "87"
      @method.call("%d", "0xc4").should == "196"
    end

    it "raises TypeError exception if cannot convert to Integer" do
      -> {
        @method.call("%b", Object.new)
      }.should raise_error(TypeError)
    end

    ["b", "B"].each do |f|
      describe f do
        it "converts argument as a binary number" do
          @method.call("%#{f}", 10).should == "1010"
        end

        it "displays negative number as a two's complement prefixed with '..1'" do
          @method.call("%#{f}", -10).should == "..1" + "0110"
        end

        it "collapse negative number representation if it equals 1" do
          @method.call("%#{f}", -1).should_not == "..11"
          @method.call("%#{f}", -1).should == "..1"
        end
      end
    end

    ["d", "i", "u"].each do |f|
      describe f do
        it "converts argument as a decimal number" do
          @method.call("%#{f}", 112).should == "112"
          @method.call("%#{f}", -112).should == "-112"
        end

        it "works well with large numbers" do
          @method.call("%#{f}", 1234567890987654321).should == "1234567890987654321"
        end
      end
    end

    describe "o" do
      it "converts argument as an octal number" do
        @method.call("%o", 87).should == "127"
      end

      it "displays negative number as a two's complement prefixed with '..7'" do
        @method.call("%o", -87).should == "..7" + "651"
      end

      it "collapse negative number representation if it equals 7" do
        @method.call("%o", -1).should_not == "..77"
        @method.call("%o", -1).should == "..7"
      end
    end

    describe "x" do
      it "converts argument as a hexadecimal number" do
        @method.call("%x", 196).should == "c4"
      end

      it "displays negative number as a two's complement prefixed with '..f'" do
        @method.call("%x", -196).should == "..f" + "3c"
      end

      it "collapse negative number representation if it equals f" do
        @method.call("%x", -1).should_not == "..ff"
        @method.call("%x", -1).should == "..f"
      end
    end

    describe "X" do
      it "converts argument as a hexadecimal number with uppercase letters" do
        @method.call("%X", 196).should == "C4"
      end

      it "displays negative number as a two's complement prefixed with '..f'" do
        @method.call("%X", -196).should == "..F" + "3C"
      end

      it "collapse negative number representation if it equals F" do
        @method.call("%X", -1).should_not == "..FF"
        @method.call("%X", -1).should == "..F"
      end
    end
  end

  describe "float formats" do
    it "converts argument into Float" do
      obj = mock("float")
      obj.should_receive(:to_f).and_return(9.6)
      @method.call("%f", obj).should == "9.600000"
    end

    it "raises TypeError exception if cannot convert to Float" do
      -> {
        @method.call("%f", Object.new)
      }.should raise_error(TypeError)
    end

    {"e" => "e", "E" => "E"}.each_pair do |f, exp|
      describe f do
        it "converts argument into exponential notation [-]d.dddddde[+-]dd" do
          @method.call("%#{f}", 109.52).should == "1.095200#{exp}+02"
          @method.call("%#{f}", -109.52).should == "-1.095200#{exp}+02"
          @method.call("%#{f}", 0.10952).should == "1.095200#{exp}-01"
          @method.call("%#{f}", -0.10952).should == "-1.095200#{exp}-01"
        end

        it "cuts excessive digits and keeps only 6 ones" do
          @method.call("%#{f}", 1.123456789).should == "1.123457#{exp}+00"
        end

        it "rounds the last significant digit to the closest one" do
          @method.call("%#{f}", 1.555555555).should == "1.555556#{exp}+00"
          @method.call("%#{f}", -1.555555555).should == "-1.555556#{exp}+00"
          @method.call("%#{f}", 1.444444444).should == "1.444444#{exp}+00"
        end

        it "displays Float::INFINITY as Inf" do
          @method.call("%#{f}", Float::INFINITY).should == "Inf"
          @method.call("%#{f}", -Float::INFINITY).should == "-Inf"
        end

        it "displays Float::NAN as NaN" do
          @method.call("%#{f}", Float::NAN).should == "NaN"
          @method.call("%#{f}", -Float::NAN).should == "NaN"
        end
      end
    end

    describe "f" do
      it "converts floating point argument as [-]ddd.dddddd" do
        @method.call("%f", 10.952).should == "10.952000"
        @method.call("%f", -10.952).should == "-10.952000"
      end

      it "cuts excessive digits and keeps only 6 ones" do
        @method.call("%f", 1.123456789).should == "1.123457"
      end

      it "rounds the last significant digit to the closest one" do
        @method.call("%f", 1.555555555).should == "1.555556"
        @method.call("%f", -1.555555555).should == "-1.555556"
        @method.call("%f", 1.444444444).should == "1.444444"
      end

      it "displays Float::INFINITY as Inf" do
        @method.call("%f", Float::INFINITY).should == "Inf"
        @method.call("%f", -Float::INFINITY).should == "-Inf"
      end

      it "displays Float::NAN as NaN" do
        @method.call("%f", Float::NAN).should == "NaN"
        @method.call("%f", -Float::NAN).should == "NaN"
      end
    end

    {"g" => "e", "G" => "E"}.each_pair do |f, exp|
      describe f do
        context "the exponent is less than -4" do
          it "converts a floating point number using exponential form" do
            @method.call("%#{f}", 0.0000123456).should == "1.23456#{exp}-05"
            @method.call("%#{f}", -0.0000123456).should == "-1.23456#{exp}-05"

            @method.call("%#{f}", 0.000000000123456).should == "1.23456#{exp}-10"
            @method.call("%#{f}", -0.000000000123456).should == "-1.23456#{exp}-10"
          end
        end

        context "the exponent is greater than or equal to the precision (6 by default)" do
          it "converts a floating point number using exponential form" do
            @method.call("%#{f}", 1234567).should == "1.23457#{exp}+06"
            @method.call("%#{f}", 1234567890123).should == "1.23457#{exp}+12"
            @method.call("%#{f}", -1234567).should == "-1.23457#{exp}+06"
          end
        end

        context "otherwise" do
          it "converts a floating point number in dd.dddd form" do
            @method.call("%#{f}", 0.0001).should == "0.0001"
            @method.call("%#{f}", -0.0001).should == "-0.0001"
            @method.call("%#{f}", 123456).should == "123456"
            @method.call("%#{f}", -123456).should == "-123456"
          end

          it "cuts excessive digits in fractional part and keeps only 4 ones" do
            @method.call("%#{f}", 12.12341111).should == "12.1234"
            @method.call("%#{f}", -12.12341111).should == "-12.1234"
          end

          it "rounds the last significant digit to the closest one in fractional part" do
            @method.call("%#{f}", 1.555555555).should == "1.55556"
            @method.call("%#{f}", -1.555555555).should == "-1.55556"
            @method.call("%#{f}", 1.444444444).should == "1.44444"
          end

          it "cuts fraction part to have only 6 digits at all" do
            @method.call("%#{f}", 1.1234567).should == "1.12346"
            @method.call("%#{f}", 12.1234567).should == "12.1235"
            @method.call("%#{f}", 123.1234567).should == "123.123"
            @method.call("%#{f}", 1234.1234567).should == "1234.12"
            @method.call("%#{f}", 12345.1234567).should == "12345.1"
            @method.call("%#{f}", 123456.1234567).should == "123456"
          end
        end

        it "displays Float::INFINITY as Inf" do
          @method.call("%#{f}", Float::INFINITY).should == "Inf"
          @method.call("%#{f}", -Float::INFINITY).should == "-Inf"
        end

        it "displays Float::NAN as NaN" do
          @method.call("%#{f}", Float::NAN).should == "NaN"
          @method.call("%#{f}", -Float::NAN).should == "NaN"
        end
      end
    end

    describe "a" do
      it "converts floating point argument as [-]0xh.hhhhp[+-]dd" do
        @method.call("%a", 196).should == "0x1.88p+7"
        @method.call("%a", -196).should == "-0x1.88p+7"
        @method.call("%a", 196.1).should == "0x1.8833333333333p+7"
        @method.call("%a", 0.01).should == "0x1.47ae147ae147bp-7"
        @method.call("%a", -0.01).should == "-0x1.47ae147ae147bp-7"
      end

      it "displays Float::INFINITY as Inf" do
        @method.call("%a", Float::INFINITY).should == "Inf"
        @method.call("%a", -Float::INFINITY).should == "-Inf"
      end

      it "displays Float::NAN as NaN" do
        @method.call("%a", Float::NAN).should == "NaN"
        @method.call("%a", -Float::NAN).should == "NaN"
      end
    end

    describe "A" do
      it "converts floating point argument as [-]0xh.hhhhp[+-]dd and use uppercase X and P" do
        @method.call("%A", 196).should == "0X1.88P+7"
        @method.call("%A", -196).should == "-0X1.88P+7"
        @method.call("%A", 196.1).should == "0X1.8833333333333P+7"
        @method.call("%A", 0.01).should == "0X1.47AE147AE147BP-7"
        @method.call("%A", -0.01).should == "-0X1.47AE147AE147BP-7"
      end

      it "displays Float::INFINITY as Inf" do
        @method.call("%A", Float::INFINITY).should == "Inf"
        @method.call("%A", -Float::INFINITY).should == "-Inf"
      end

      it "displays Float::NAN as NaN" do
        @method.call("%A", Float::NAN).should == "NaN"
        @method.call("%A", -Float::NAN).should == "NaN"
      end
    end
  end

  describe "other formats" do
    describe "c" do
      it "displays character if argument is a numeric code of character" do
        @method.call("%c", 97).should == "a"
      end

      it "displays character if argument is a single character string" do
        @method.call("%c", "a").should == "a"
      end

      ruby_version_is ""..."3.2" do
        it "raises ArgumentError if argument is a string of several characters" do
          -> {
            @method.call("%c", "abc")
          }.should raise_error(ArgumentError, /%c requires a character/)
        end

        it "raises ArgumentError if argument is an empty string" do
          -> {
            @method.call("%c", "")
          }.should raise_error(ArgumentError, /%c requires a character/)
        end
      end

      ruby_version_is "3.2" do
        it "displays only the first character if argument is a string of several characters" do
          @method.call("%c", "abc").should == "a"
        end

        it "displays no characters if argument is an empty string" do
          @method.call("%c", "").should == ""
        end
      end

      it "raises TypeError if argument is not String or Integer and cannot be converted to them" do
        -> {
          @method.call("%c", [])
        }.should raise_error(TypeError, /no implicit conversion of Array into Integer/)
      end

      it "raises TypeError if argument is nil" do
        -> {
          @method.call("%c", nil)
        }.should raise_error(TypeError, /no implicit conversion from nil to integer/)
      end

      it "tries to convert argument to String with to_str" do
        obj = BasicObject.new
        def obj.to_str
          "a"
        end

        @method.call("%c", obj).should == "a"
      end

      it "tries to convert argument to Integer with to_int" do
        obj = BasicObject.new
        def obj.to_int
          90
        end

        @method.call("%c", obj).should == "Z"
      end

      it "raises TypeError if converting to String with to_str returns non-String" do
        obj = BasicObject.new
        def obj.to_str
          :foo
        end

        -> {
          @method.call("%c", obj)
        }.should raise_error(TypeError, /can't convert BasicObject to String/)
      end

      it "raises TypeError if converting to Integer with to_int returns non-Integer" do
        obj = BasicObject.new
        def obj.to_int
          :foo
        end

        -> {
          @method.call("%c", obj)
        }.should raise_error(TypeError, /can't convert BasicObject to Integer/)
      end
    end

    describe "p" do
      it "displays argument.inspect value" do
        obj = mock("object")
        obj.should_receive(:inspect).and_return("<inspect-result>")
        @method.call("%p", obj).should == "<inspect-result>"
      end
    end

    describe "s" do
      it "substitute argument passes as a string" do
        @method.call("%s", "abc").should == "abc"
      end

      it "substitutes '' for nil" do
        @method.call("%s", nil).should == ""
      end

      it "converts argument to string with to_s" do
        obj = mock("string")
        obj.should_receive(:to_s).and_return("abc")
        @method.call("%s", obj).should == "abc"
      end

      it "does not try to convert with to_str" do
        obj = BasicObject.new
        def obj.to_str
          "abc"
        end

        -> {
          @method.call("%s", obj)
        }.should raise_error(NoMethodError)
      end

      it "formats a partial substring without including omitted characters" do
        long_string = "aabbccddhelloddccbbaa"
        sub_string = long_string[8, 5]
        sprintf("%.#{1 * 3}s", sub_string).should == "hel"
      end

      it "formats string with precision" do
        Kernel.format("%.3s", "hello").should == "hel"
        Kernel.format("%-3.3s", "hello").should == "hel"
      end

      it "formats string with width" do
        @method.call("%6s", "abc").should == "   abc"
        @method.call("%6s", "abcdefg").should == "abcdefg"
      end

      it "formats string with width and precision" do
        @method.call("%4.6s", "abc").should == " abc"
        @method.call("%4.6s", "abcdefg").should == "abcdef"
      end

      it "formats nil with width" do
        @method.call("%6s", nil).should == "      "
      end

      it "formats nil with precision" do
        @method.call("%.6s", nil).should == ""
      end

      it "formats nil with width and precision" do
        @method.call("%4.6s", nil).should == "    "
      end

      it "formats multibyte string with precision" do
        Kernel.format("%.2s", "été").should == "ét"
      end

      it "preserves encoding of the format string" do
        str = format('%s'.encode(Encoding::UTF_8), 'foobar')
        str.encoding.should == Encoding::UTF_8

        str = format('%s'.encode(Encoding::US_ASCII), 'foobar')
        str.encoding.should == Encoding::US_ASCII
      end
    end

    describe "%" do
      it "alone raises an ArgumentError" do
        -> {
          @method.call("%")
        }.should raise_error(ArgumentError)
      end

      it "is escaped by %" do
        @method.call("%%").should == "%"
        @method.call("%%d", 10).should == "%d"
      end
    end
  end

  describe "flags" do
    describe "space" do
      context "applies to numeric formats bBdiouxXeEfgGaA" do
        it "leaves a space at the start of non-negative numbers" do
          @method.call("% b", 10).should == " 1010"
          @method.call("% B", 10).should == " 1010"
          @method.call("% d", 112).should == " 112"
          @method.call("% i", 112).should == " 112"
          @method.call("% o", 87).should == " 127"
          @method.call("% u", 112).should == " 112"
          @method.call("% x", 196).should == " c4"
          @method.call("% X", 196).should == " C4"

          @method.call("% e", 109.52).should == " 1.095200e+02"
          @method.call("% E", 109.52).should == " 1.095200E+02"
          @method.call("% f", 10.952).should == " 10.952000"
          @method.call("% g", 12.1234).should == " 12.1234"
          @method.call("% G", 12.1234).should == " 12.1234"
          @method.call("% a", 196).should == " 0x1.88p+7"
          @method.call("% A", 196).should == " 0X1.88P+7"
        end

        it "does not leave a space at the start of negative numbers" do
          @method.call("% b", -10).should == "-1010"
          @method.call("% B", -10).should == "-1010"
          @method.call("% d", -112).should == "-112"
          @method.call("% i", -112).should == "-112"
          @method.call("% o", -87).should == "-127"
          @method.call("% u", -112).should == "-112"
          @method.call("% x", -196).should == "-c4"
          @method.call("% X", -196).should == "-C4"

          @method.call("% e", -109.52).should == "-1.095200e+02"
          @method.call("% E", -109.52).should == "-1.095200E+02"
          @method.call("% f", -10.952).should == "-10.952000"
          @method.call("% g", -12.1234).should == "-12.1234"
          @method.call("% G", -12.1234).should == "-12.1234"
          @method.call("% a", -196).should == "-0x1.88p+7"
          @method.call("% A", -196).should == "-0X1.88P+7"
        end

        it "prevents converting negative argument to two's complement form" do
          @method.call("% b", -10).should == "-1010"
          @method.call("% B", -10).should == "-1010"
          @method.call("% o", -87).should == "-127"
          @method.call("% x", -196).should == "-c4"
          @method.call("% X", -196).should == "-C4"
        end

        it "treats several white spaces as one" do
          @method.call("%     b", 10).should == " 1010"
          @method.call("%     B", 10).should == " 1010"
          @method.call("%     d", 112).should == " 112"
          @method.call("%     i", 112).should == " 112"
          @method.call("%     o", 87).should == " 127"
          @method.call("%     u", 112).should == " 112"
          @method.call("%     x", 196).should == " c4"
          @method.call("%     X", 196).should == " C4"

          @method.call("%     e", 109.52).should == " 1.095200e+02"
          @method.call("%     E", 109.52).should == " 1.095200E+02"
          @method.call("%     f", 10.952).should == " 10.952000"
          @method.call("%     g", 12.1234).should == " 12.1234"
          @method.call("%     G", 12.1234).should == " 12.1234"
          @method.call("%     a", 196).should == " 0x1.88p+7"
          @method.call("%     A", 196).should == " 0X1.88P+7"
        end
      end
    end

    describe "(digit)$" do
      it "specifies the absolute argument number for this field" do
        @method.call("%2$b", 0, 10).should == "1010"
        @method.call("%2$B", 0, 10).should == "1010"
        @method.call("%2$d", 0, 112).should == "112"
        @method.call("%2$i", 0, 112).should == "112"
        @method.call("%2$o", 0, 87).should == "127"
        @method.call("%2$u", 0, 112).should == "112"
        @method.call("%2$x", 0, 196).should == "c4"
        @method.call("%2$X", 0, 196).should == "C4"

        @method.call("%2$e", 0, 109.52).should == "1.095200e+02"
        @method.call("%2$E", 0, 109.52).should == "1.095200E+02"
        @method.call("%2$f", 0, 10.952).should == "10.952000"
        @method.call("%2$g", 0, 12.1234).should == "12.1234"
        @method.call("%2$G", 0, 12.1234).should == "12.1234"
        @method.call("%2$a", 0, 196).should == "0x1.88p+7"
        @method.call("%2$A", 0, 196).should == "0X1.88P+7"

        @method.call("%2$c", 1, 97).should == "a"
        @method.call("%2$p", "a", []).should == "[]"
        @method.call("%2$s", "-", "abc").should == "abc"
      end

      it "raises exception if argument number is bigger than actual arguments list" do
        -> {
          @method.call("%4$d", 1, 2, 3)
        }.should raise_error(ArgumentError)
      end

      it "ignores '-' sign" do
        @method.call("%2$d", 1, 2, 3).should == "2"
        @method.call("%-2$d", 1, 2, 3).should == "2"
      end

      it "raises ArgumentError exception when absolute and relative argument numbers are mixed" do
        -> {
          @method.call("%1$d %d", 1, 2)
        }.should raise_error(ArgumentError)
      end
    end

    describe "#" do
      context "applies to format o" do
        it "increases the precision until the first digit will be `0' if it is not formatted as complements" do
          @method.call("%#o", 87).should == "0127"
        end

        it "does nothing for negative argument" do
          @method.call("%#o", -87).should == "..7651"
        end
      end

      context "applies to formats bBxX" do
        it "prefixes the result with 0x, 0X, 0b and 0B respectively for non-zero argument" do
          @method.call("%#b", 10).should == "0b1010"
          @method.call("%#b", -10).should == "0b..10110"
          @method.call("%#B", 10).should == "0B1010"
          @method.call("%#B", -10).should == "0B..10110"

          @method.call("%#x", 196).should == "0xc4"
          @method.call("%#x", -196).should == "0x..f3c"
          @method.call("%#X", 196).should == "0XC4"
          @method.call("%#X", -196).should == "0X..F3C"
        end

        it "does nothing for zero argument" do
          @method.call("%#b", 0).should == "0"
          @method.call("%#B", 0).should == "0"

          @method.call("%#o", 0).should == "0"

          @method.call("%#x", 0).should == "0"
          @method.call("%#X", 0).should == "0"
        end
      end

      context "applies to formats aAeEfgG" do
        it "forces a decimal point to be added, even if no digits follow" do
          @method.call("%#.0a", 16.25).should == "0x1.p+4"
          @method.call("%#.0A", 16.25).should == "0X1.P+4"

          @method.call("%#.0e", 100).should == "1.e+02"
          @method.call("%#.0E", 100).should == "1.E+02"

          @method.call("%#.0f", 123.4).should == "123."

          @method.call("%#g", 123456).should == "123456."
          @method.call("%#G", 123456).should == "123456."
        end

        it "changes format from dd.dddd to exponential form for gG" do
          @method.call("%#.0g", 123.4).should_not == "123."
          @method.call("%#.0g", 123.4).should == "1.e+02"
        end
      end

      context "applies to gG" do
        it "does not remove trailing zeros" do
          @method.call("%#g", 123.4).should == "123.400"
          @method.call("%#g", 123.4).should == "123.400"
        end
      end
    end

    describe "+" do
      context "applies to numeric formats bBdiouxXaAeEfgG" do
        it "adds a leading plus sign to non-negative numbers" do
          @method.call("%+b", 10).should == "+1010"
          @method.call("%+B", 10).should == "+1010"
          @method.call("%+d", 112).should == "+112"
          @method.call("%+i", 112).should == "+112"
          @method.call("%+o", 87).should == "+127"
          @method.call("%+u", 112).should == "+112"
          @method.call("%+x", 196).should == "+c4"
          @method.call("%+X", 196).should == "+C4"

          @method.call("%+e", 109.52).should == "+1.095200e+02"
          @method.call("%+E", 109.52).should == "+1.095200E+02"
          @method.call("%+f", 10.952).should == "+10.952000"
          @method.call("%+g", 12.1234).should == "+12.1234"
          @method.call("%+G", 12.1234).should == "+12.1234"
          @method.call("%+a", 196).should == "+0x1.88p+7"
          @method.call("%+A", 196).should == "+0X1.88P+7"
        end

        it "does not use two's complement form for negative numbers for formats bBoxX" do
          @method.call("%+b", -10).should == "-1010"
          @method.call("%+B", -10).should == "-1010"
          @method.call("%+o", -87).should == "-127"
          @method.call("%+x", -196).should == "-c4"
          @method.call("%+X", -196).should == "-C4"
        end
      end
    end

    describe "-" do
      it "left-justifies the result of conversion if width is specified" do
        @method.call("%-10b", 10).should == "1010      "
        @method.call("%-10B", 10).should == "1010      "
        @method.call("%-10d", 112).should == "112       "
        @method.call("%-10i", 112).should == "112       "
        @method.call("%-10o", 87).should == "127       "
        @method.call("%-10u", 112).should == "112       "
        @method.call("%-10x", 196).should == "c4        "
        @method.call("%-10X", 196).should == "C4        "

        @method.call("%-20e", 109.52).should == "1.095200e+02        "
        @method.call("%-20E", 109.52).should == "1.095200E+02        "
        @method.call("%-20f", 10.952).should == "10.952000           "
        @method.call("%-20g", 12.1234).should == "12.1234             "
        @method.call("%-20G", 12.1234).should == "12.1234             "
        @method.call("%-20a", 196).should == "0x1.88p+7           "
        @method.call("%-20A", 196).should == "0X1.88P+7           "

        @method.call("%-10c", 97).should == "a         "
        @method.call("%-10p", []).should == "[]        "
        @method.call("%-10s", "abc").should == "abc       "
      end
    end

    describe "0 (zero)" do
      context "applies to numeric formats bBdiouxXaAeEfgG and width is specified" do
        it "pads with zeros, not spaces" do
          @method.call("%010b", 10).should == "0000001010"
          @method.call("%010B", 10).should == "0000001010"
          @method.call("%010d", 112).should == "0000000112"
          @method.call("%010i", 112).should == "0000000112"
          @method.call("%010o", 87).should == "0000000127"
          @method.call("%010u", 112).should == "0000000112"
          @method.call("%010x", 196).should == "00000000c4"
          @method.call("%010X", 196).should == "00000000C4"

          @method.call("%020e", 109.52).should == "000000001.095200e+02"
          @method.call("%020E", 109.52).should == "000000001.095200E+02"
          @method.call("%020f", 10.952).should == "0000000000010.952000"
          @method.call("%020g", 12.1234).should == "000000000000012.1234"
          @method.call("%020G", 12.1234).should == "000000000000012.1234"
          @method.call("%020a", 196).should == "0x000000000001.88p+7"
          @method.call("%020A", 196).should == "0X000000000001.88P+7"
        end

        it "uses radix-1 when displays negative argument as a two's complement" do
          @method.call("%010b", -10).should == "..11110110"
          @method.call("%010B", -10).should == "..11110110"
          @method.call("%010o", -87).should == "..77777651"
          @method.call("%010x", -196).should == "..ffffff3c"
          @method.call("%010X", -196).should == "..FFFFFF3C"
        end
      end
    end

    describe "*" do
      it "uses the previous argument as the field width" do
        @method.call("%*b", 10, 10).should == "      1010"
        @method.call("%*B", 10, 10).should == "      1010"
        @method.call("%*d", 10, 112).should == "       112"
        @method.call("%*i", 10, 112).should == "       112"
        @method.call("%*o", 10, 87).should == "       127"
        @method.call("%*u", 10, 112).should == "       112"
        @method.call("%*x", 10, 196).should == "        c4"
        @method.call("%*X", 10, 196).should == "        C4"

        @method.call("%*e", 20, 109.52).should == "        1.095200e+02"
        @method.call("%*E", 20, 109.52).should == "        1.095200E+02"
        @method.call("%*f", 20, 10.952).should == "           10.952000"
        @method.call("%*g", 20, 12.1234).should == "             12.1234"
        @method.call("%*G", 20, 12.1234).should == "             12.1234"
        @method.call("%*a", 20, 196).should == "           0x1.88p+7"
        @method.call("%*A", 20, 196).should == "           0X1.88P+7"

        @method.call("%*c", 10, 97).should == "         a"
        @method.call("%*p", 10, []).should == "        []"
        @method.call("%*s", 10, "abc").should == "       abc"
      end

      it "left-justifies the result if width is negative" do
        @method.call("%*b", -10, 10).should == "1010      "
        @method.call("%*B", -10, 10).should == "1010      "
        @method.call("%*d", -10, 112).should == "112       "
        @method.call("%*i", -10, 112).should == "112       "
        @method.call("%*o", -10, 87).should == "127       "
        @method.call("%*u", -10, 112).should == "112       "
        @method.call("%*x", -10, 196).should == "c4        "
        @method.call("%*X", -10, 196).should == "C4        "

        @method.call("%*e", -20, 109.52).should == "1.095200e+02        "
        @method.call("%*E", -20, 109.52).should == "1.095200E+02        "
        @method.call("%*f", -20, 10.952).should == "10.952000           "
        @method.call("%*g", -20, 12.1234).should == "12.1234             "
        @method.call("%*G", -20, 12.1234).should == "12.1234             "
        @method.call("%*a", -20, 196).should == "0x1.88p+7           "
        @method.call("%*A", -20, 196).should == "0X1.88P+7           "

        @method.call("%*c", -10, 97).should == "a         "
        @method.call("%*p", -10, []).should == "[]        "
        @method.call("%*s", -10, "abc").should == "abc       "
      end

      it "uses the specified argument as the width if * is followed by a number and $" do
        @method.call("%1$*2$b", 10, 10).should == "      1010"
        @method.call("%1$*2$B", 10, 10).should == "      1010"
        @method.call("%1$*2$d", 112, 10).should == "       112"
        @method.call("%1$*2$i", 112, 10).should == "       112"
        @method.call("%1$*2$o", 87, 10).should == "       127"
        @method.call("%1$*2$u", 112, 10).should == "       112"
        @method.call("%1$*2$x", 196, 10).should == "        c4"
        @method.call("%1$*2$X", 196, 10).should == "        C4"

        @method.call("%1$*2$e", 109.52, 20).should == "        1.095200e+02"
        @method.call("%1$*2$E", 109.52, 20).should == "        1.095200E+02"
        @method.call("%1$*2$f", 10.952, 20).should == "           10.952000"
        @method.call("%1$*2$g", 12.1234, 20).should == "             12.1234"
        @method.call("%1$*2$G", 12.1234, 20).should == "             12.1234"
        @method.call("%1$*2$a", 196, 20).should == "           0x1.88p+7"
        @method.call("%1$*2$A", 196, 20).should == "           0X1.88P+7"

        @method.call("%1$*2$c", 97, 10).should == "         a"
        @method.call("%1$*2$p", [], 10).should == "        []"
        @method.call("%1$*2$s", "abc", 10).should == "       abc"
      end

      it "left-justifies the result if specified with $ argument is negative" do
        @method.call("%1$*2$b", 10, -10).should == "1010      "
        @method.call("%1$*2$B", 10, -10).should == "1010      "
        @method.call("%1$*2$d", 112, -10).should == "112       "
        @method.call("%1$*2$i", 112, -10).should == "112       "
        @method.call("%1$*2$o", 87, -10).should == "127       "
        @method.call("%1$*2$u", 112, -10).should == "112       "
        @method.call("%1$*2$x", 196, -10).should == "c4        "
        @method.call("%1$*2$X", 196, -10).should == "C4        "

        @method.call("%1$*2$e", 109.52, -20).should == "1.095200e+02        "
        @method.call("%1$*2$E", 109.52, -20).should == "1.095200E+02        "
        @method.call("%1$*2$f", 10.952, -20).should == "10.952000           "
        @method.call("%1$*2$g", 12.1234, -20).should == "12.1234             "
        @method.call("%1$*2$G", 12.1234, -20).should == "12.1234             "
        @method.call("%1$*2$a", 196, -20).should == "0x1.88p+7           "
        @method.call("%1$*2$A", 196, -20).should == "0X1.88P+7           "

        @method.call("%1$*2$c", 97, -10).should == "a         "
        @method.call("%1$*2$p", [], -10).should == "[]        "
        @method.call("%1$*2$s", "abc", -10).should == "abc       "
      end

      it "raises ArgumentError when is mixed with width" do
        -> {
          @method.call("%*10d", 10, 112)
        }.should raise_error(ArgumentError)
      end
    end
  end

  describe "width" do
    it "specifies the minimum number of characters that will be written to the result" do
      @method.call("%10b", 10).should == "      1010"
      @method.call("%10B", 10).should == "      1010"
      @method.call("%10d", 112).should == "       112"
      @method.call("%10i", 112).should == "       112"
      @method.call("%10o", 87).should == "       127"
      @method.call("%10u", 112).should == "       112"
      @method.call("%10x", 196).should == "        c4"
      @method.call("%10X", 196).should == "        C4"

      @method.call("%20e", 109.52).should == "        1.095200e+02"
      @method.call("%20E", 109.52).should == "        1.095200E+02"
      @method.call("%20f", 10.952).should == "           10.952000"
      @method.call("%20g", 12.1234).should == "             12.1234"
      @method.call("%20G", 12.1234).should == "             12.1234"
      @method.call("%20a", 196).should == "           0x1.88p+7"
      @method.call("%20A", 196).should == "           0X1.88P+7"

      @method.call("%10c", 97).should == "         a"
      @method.call("%10p", []).should == "        []"
      @method.call("%10s", "abc").should == "       abc"
    end

    it "is ignored if argument's actual length is greater" do
      @method.call("%5d", 1234567890).should == "1234567890"
    end
  end

  describe "precision" do
    context "integer types" do
      it "controls the number of decimal places displayed" do
        @method.call("%.6b", 10).should == "001010"
        @method.call("%.6B", 10).should == "001010"
        @method.call("%.5d", 112).should == "00112"
        @method.call("%.5i", 112).should == "00112"
        @method.call("%.5o", 87).should == "00127"
        @method.call("%.5u", 112).should == "00112"

        @method.call("%.5x", 196).should == "000c4"
        @method.call("%.5X", 196).should == "000C4"
      end
    end

    context "float types" do
      it "controls the number of decimal places displayed in fraction part" do
        @method.call("%.10e", 109.52).should == "1.0952000000e+02"
        @method.call("%.10E", 109.52).should == "1.0952000000E+02"
        @method.call("%.10f", 10.952).should == "10.9520000000"
        @method.call("%.10a", 196).should == "0x1.8800000000p+7"
        @method.call("%.10A", 196).should == "0X1.8800000000P+7"
      end

      it "does not affect G format" do
        @method.call("%.10g", 12.1234).should == "12.1234"
        @method.call("%.10g", 123456789).should == "123456789"
      end
    end

    context "string formats" do
      it "determines the maximum number of characters to be copied from the string" do
        @method.call("%.1p", [1]).should == "["
        @method.call("%.2p", [1]).should == "[1"
        @method.call("%.10p", [1]).should == "[1]"
        @method.call("%.0p", [1]).should == ""

        @method.call("%.1s", "abc").should == "a"
        @method.call("%.2s", "abc").should == "ab"
        @method.call("%.10s", "abc").should == "abc"
        @method.call("%.0s", "abc").should == ""
      end
    end
  end

  describe "reference by name" do
    describe "%<name>s style" do
      it "uses value passed in a hash argument" do
        @method.call("%<foo>d", foo: 123).should == "123"
      end

      it "supports flags, width, precision and type" do
        @method.call("%+20.10<foo>f", foo: 10.952).should == "      +10.9520000000"
      end

      it "allows to place name in any position" do
        @method.call("%+15.5<foo>f", foo: 10.952).should == "      +10.95200"
        @method.call("%+15<foo>.5f", foo: 10.952).should == "      +10.95200"
        @method.call("%+<foo>15.5f", foo: 10.952).should == "      +10.95200"
        @method.call("%<foo>+15.5f", foo: 10.952).should == "      +10.95200"
      end

      it "cannot be mixed with unnamed style" do
        -> {
          @method.call("%d %<foo>d", 1, foo: "123")
        }.should raise_error(ArgumentError)
      end
    end

    describe "%{name} style" do
      it "uses value passed in a hash argument" do
        @method.call("%{foo}", foo: 123).should == "123"
      end

      it "does not support type style" do
        @method.call("%{foo}d", foo: 123).should == "123d"
      end

      it "supports flags, width and precision" do
        @method.call("%-20.5{foo}", foo: "123456789").should == "12345               "
      end

      it "cannot be mixed with unnamed style" do
        -> {
          @method.call("%d %{foo}", 1, foo: "123")
        }.should raise_error(ArgumentError)
      end

      it "raises KeyError when there is no matching key" do
        -> {
          @method.call("%{foo}", {})
        }.should raise_error(KeyError)
      end

      it "converts value to String with to_s" do
        obj = Object.new
        def obj.to_s; end
        def obj.to_str; end

        obj.should_receive(:to_s).and_return("42")
        obj.should_not_receive(:to_str)

        @method.call("%{foo}", foo: obj).should == "42"
      end
    end
  end

  describe "faulty key" do
    before :each do
      @object = { foooo: 1 }
    end

    it "raises a KeyError" do
      -> {
        @method.call("%<foo>s", @object)
      }.should raise_error(KeyError)
    end

    it "sets the Hash as the receiver of KeyError" do
      -> {
        @method.call("%<foo>s", @object)
      }.should raise_error(KeyError) { |err|
        err.receiver.should equal(@object)
      }
    end

    it "sets the unmatched key as the key of KeyError" do
      -> {
        @method.call("%<foo>s", @object)
      }.should raise_error(KeyError) { |err|
        err.key.to_s.should == 'foo'
      }
    end
  end

  it "does not raise error when passed more arguments than needed" do
    sprintf("%s %d %c", "string", 2, "c", []).should == "string 2 c"
  end
end
