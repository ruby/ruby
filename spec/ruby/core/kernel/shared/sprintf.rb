describe :kernel_sprintf, shared: true do
  def format(*args)
    @method.call(*args)
  end

  describe "integer formats" do
    it "converts argument into Integer with to_int" do
      obj = Object.new
      def obj.to_i; 10; end
      def obj.to_int; 10; end

      obj.should_receive(:to_int).and_return(10)
      format("%b", obj).should == "1010"
    end

    it "converts argument into Integer with to_i if to_int isn't available" do
      obj = Object.new
      def obj.to_i; 10; end

      obj.should_receive(:to_i).and_return(10)
      format("%b", obj).should == "1010"
    end

    it "converts String argument with Kernel#Integer" do
      format("%d", "0b1010").should == "10"
      format("%d", "112").should == "112"
      format("%d", "0127").should == "87"
      format("%d", "0xc4").should == "196"
    end

    it "raises TypeError exception if cannot convert to Integer" do
      -> () {
        format("%b", Object.new)
      }.should raise_error(TypeError)
    end

    ["b", "B"].each do |f|
      describe f do
        it "converts argument as a binary number" do
          format("%#{f}", 10).should == "1010"
        end

        it "displays negative number as a two's complement prefixed with '..1'" do
          format("%#{f}", -10).should == "..1" + "0110"
        end

        it "collapse negative number representation if it equals 1" do
          format("%#{f}", -1).should_not == "..11"
          format("%#{f}", -1).should == "..1"
        end
      end
    end

    ["d", "i", "u"].each do |f|
      describe f do
        it "converts argument as a decimal number" do
          format("%#{f}", 112).should == "112"
          format("%#{f}", -112).should == "-112"
        end

        it "works well with large numbers" do
          format("%#{f}", 1234567890987654321).should == "1234567890987654321"
        end
      end
    end

    describe "o" do
      it "converts argument as an octal number" do
        format("%o", 87).should == "127"
      end

      it "displays negative number as a two's complement prefixed with '..7'" do
        format("%o", -87).should == "..7" + "651"
      end

      it "collapse negative number representation if it equals 7" do
        format("%o", -1).should_not == "..77"
        format("%o", -1).should == "..7"
      end
    end

    describe "x" do
      it "converts argument as a hexadecimal number" do
        format("%x", 196).should == "c4"
      end

      it "displays negative number as a two's complement prefixed with '..f'" do
        format("%x", -196).should == "..f" + "3c"
      end

      it "collapse negative number representation if it equals f" do
        format("%x", -1).should_not == "..ff"
        format("%x", -1).should == "..f"
      end
    end

    describe "X" do
      it "converts argument as a hexadecimal number with uppercase letters" do
        format("%X", 196).should == "C4"
      end

      it "displays negative number as a two's complement prefixed with '..f'" do
        format("%X", -196).should == "..F" + "3C"
      end

      it "collapse negative number representation if it equals F" do
        format("%X", -1).should_not == "..FF"
        format("%X", -1).should == "..F"
      end
    end
  end

  describe "float formats" do
    it "converts argument into Float" do
      obj = mock("float")
      obj.should_receive(:to_f).and_return(9.6)
      format("%f", obj).should == "9.600000"
    end

    it "raises TypeError exception if cannot convert to Float" do
      -> () {
        format("%f", Object.new)
      }.should raise_error(TypeError)
    end

    {"e" => "e", "E" => "E"}.each_pair do |f, exp|
      describe f do
        it "converts argument into exponential notation [-]d.dddddde[+-]dd" do
          format("%#{f}", 109.52).should == "1.095200#{exp}+02"
          format("%#{f}", -109.52).should == "-1.095200#{exp}+02"
          format("%#{f}", 0.10952).should == "1.095200#{exp}-01"
          format("%#{f}", -0.10952).should == "-1.095200#{exp}-01"
        end

        it "cuts excessive digits and keeps only 6 ones" do
          format("%#{f}", 1.123456789).should == "1.123457#{exp}+00"
        end

        it "rounds the last significant digit to the closest one" do
          format("%#{f}", 1.555555555).should == "1.555556#{exp}+00"
          format("%#{f}", -1.555555555).should == "-1.555556#{exp}+00"
          format("%#{f}", 1.444444444).should == "1.444444#{exp}+00"
        end

        it "displays Float::INFINITY as Inf" do
          format("%#{f}", Float::INFINITY).should == "Inf"
          format("%#{f}", -Float::INFINITY).should == "-Inf"
        end

        it "displays Float::NAN as NaN" do
          format("%#{f}", Float::NAN).should == "NaN"
          format("%#{f}", -Float::NAN).should == "NaN"
        end
      end
    end

    describe "f" do
      it "converts floating point argument as [-]ddd.dddddd" do
        format("%f", 10.952).should == "10.952000"
        format("%f", -10.952).should == "-10.952000"
      end

      it "cuts excessive digits and keeps only 6 ones" do
        format("%f", 1.123456789).should == "1.123457"
      end

      it "rounds the last significant digit to the closest one" do
        format("%f", 1.555555555).should == "1.555556"
        format("%f", -1.555555555).should == "-1.555556"
        format("%f", 1.444444444).should == "1.444444"
      end

      it "displays Float::INFINITY as Inf" do
        format("%f", Float::INFINITY).should == "Inf"
        format("%f", -Float::INFINITY).should == "-Inf"
      end

      it "displays Float::NAN as NaN" do
        format("%f", Float::NAN).should == "NaN"
        format("%f", -Float::NAN).should == "NaN"
      end
    end

    {"g" => "e", "G" => "E"}.each_pair do |f, exp|
      describe f do
        context "the exponent is less than -4" do
          it "converts a floating point number using exponential form" do
            format("%#{f}", 0.0000123456).should == "1.23456#{exp}-05"
            format("%#{f}", -0.0000123456).should == "-1.23456#{exp}-05"

            format("%#{f}", 0.000000000123456).should == "1.23456#{exp}-10"
            format("%#{f}", -0.000000000123456).should == "-1.23456#{exp}-10"
          end
        end

        context "the exponent is greater than or equal to the precision (6 by default)" do
          it "converts a floating point number using exponential form" do
            format("%#{f}", 1234567).should == "1.23457#{exp}+06"
            format("%#{f}", 1234567890123).should == "1.23457#{exp}+12"
            format("%#{f}", -1234567).should == "-1.23457#{exp}+06"
          end
        end

        context "otherwise" do
          it "converts a floating point number in dd.dddd form" do
            format("%#{f}", 0.0001).should == "0.0001"
            format("%#{f}", -0.0001).should == "-0.0001"
            format("%#{f}", 123456).should == "123456"
            format("%#{f}", -123456).should == "-123456"
          end

          it "cuts excessive digits in fractional part and keeps only 4 ones" do
            format("%#{f}", 12.12341111).should == "12.1234"
            format("%#{f}", -12.12341111).should == "-12.1234"
          end

          it "rounds the last significant digit to the closest one in fractional part" do
            format("%#{f}", 1.555555555).should == "1.55556"
            format("%#{f}", -1.555555555).should == "-1.55556"
            format("%#{f}", 1.444444444).should == "1.44444"
          end

          it "cuts fraction part to have only 6 digits at all" do
            format("%#{f}", 1.1234567).should == "1.12346"
            format("%#{f}", 12.1234567).should == "12.1235"
            format("%#{f}", 123.1234567).should == "123.123"
            format("%#{f}", 1234.1234567).should == "1234.12"
            format("%#{f}", 12345.1234567).should == "12345.1"
            format("%#{f}", 123456.1234567).should == "123456"
          end
        end

        it "displays Float::INFINITY as Inf" do
          format("%#{f}", Float::INFINITY).should == "Inf"
          format("%#{f}", -Float::INFINITY).should == "-Inf"
        end

        it "displays Float::NAN as NaN" do
          format("%#{f}", Float::NAN).should == "NaN"
          format("%#{f}", -Float::NAN).should == "NaN"
        end
      end
    end

    describe "a" do
      it "converts floating point argument as [-]0xh.hhhhp[+-]dd" do
        format("%a", 196).should == "0x1.88p+7"
        format("%a", -196).should == "-0x1.88p+7"
        format("%a", 196.1).should == "0x1.8833333333333p+7"
        format("%a", 0.01).should == "0x1.47ae147ae147bp-7"
        format("%a", -0.01).should == "-0x1.47ae147ae147bp-7"
      end

      it "displays Float::INFINITY as Inf" do
        format("%a", Float::INFINITY).should == "Inf"
        format("%a", -Float::INFINITY).should == "-Inf"
      end

      it "displays Float::NAN as NaN" do
        format("%a", Float::NAN).should == "NaN"
        format("%a", -Float::NAN).should == "NaN"
      end
    end

    describe "A" do
      it "converts floating point argument as [-]0xh.hhhhp[+-]dd and use uppercase X and P" do
        format("%A", 196).should == "0X1.88P+7"
        format("%A", -196).should == "-0X1.88P+7"
        format("%A", 196.1).should == "0X1.8833333333333P+7"
        format("%A", 0.01).should == "0X1.47AE147AE147BP-7"
        format("%A", -0.01).should == "-0X1.47AE147AE147BP-7"
      end

      it "displays Float::INFINITY as Inf" do
        format("%A", Float::INFINITY).should == "Inf"
        format("%A", -Float::INFINITY).should == "-Inf"
      end

      it "displays Float::NAN as NaN" do
        format("%A", Float::NAN).should == "NaN"
        format("%A", -Float::NAN).should == "NaN"
      end
    end
  end

  describe "other formats" do
    describe "c" do
      it "displays character if argument is a numeric code of character" do
        format("%c", 97).should == "a"
      end

      it "displays character if argument is a single character string" do
        format("%c", "a").should == "a"
      end

      it "raises ArgumentError if argument is a string of several characters" do
        -> () {
          format("%c", "abc")
        }.should raise_error(ArgumentError)
      end

      it "raises ArgumentError if argument is an empty string" do
        -> () {
          format("%c", "")
        }.should raise_error(ArgumentError)
      end

      it "supports Unicode characters" do
        format("%c", 1286).should == "Ԇ"
        format("%c", "ش").should == "ش"
      end
    end

    describe "p" do
      it "displays argument.inspect value" do
        obj = mock("object")
        obj.should_receive(:inspect).and_return("<inspect-result>")
        format("%p", obj).should == "<inspect-result>"
      end
    end

    describe "s" do
      it "substitute argument passes as a string" do
        format("%s", "abc").should == "abc"
      end

      it "converts argument to string with to_s" do
        obj = mock("string")
        obj.should_receive(:to_s).and_return("abc")
        format("%s", obj).should == "abc"
      end

      it "does not try to convert with to_str" do
        obj = BasicObject.new
        def obj.to_str
          "abc"
        end

        -> () {
          format("%s", obj)
        }.should raise_error(NoMethodError)
      end
    end

    describe "%" do
      ruby_version_is ""..."2.5" do
        it "alone displays the percent sign" do
          format("%").should == "%"
        end
      end

      ruby_version_is "2.5" do
        it "alone raises an ArgumentError" do
          -> {
            format("%")
          }.should raise_error(ArgumentError)
        end
      end

      it "is escaped by %" do
        format("%%").should == "%"
        format("%%d", 10).should == "%d"
      end
    end
  end

  describe "flags" do
    describe "space" do
      context "applies to numeric formats bBdiouxXeEfgGaA" do
        it "leaves a space at the start of non-negative numbers" do
          format("% b", 10).should == " 1010"
          format("% B", 10).should == " 1010"
          format("% d", 112).should == " 112"
          format("% i", 112).should == " 112"
          format("% o", 87).should == " 127"
          format("% u", 112).should == " 112"
          format("% x", 196).should == " c4"
          format("% X", 196).should == " C4"

          format("% e", 109.52).should == " 1.095200e+02"
          format("% E", 109.52).should == " 1.095200E+02"
          format("% f", 10.952).should == " 10.952000"
          format("% g", 12.1234).should == " 12.1234"
          format("% G", 12.1234).should == " 12.1234"
          format("% a", 196).should == " 0x1.88p+7"
          format("% A", 196).should == " 0X1.88P+7"
        end

        it "does not leave a space at the start of negative numbers" do
          format("% b", -10).should == "-1010"
          format("% B", -10).should == "-1010"
          format("% d", -112).should == "-112"
          format("% i", -112).should == "-112"
          format("% o", -87).should == "-127"
          format("% u", -112).should == "-112"
          format("% x", -196).should == "-c4"
          format("% X", -196).should == "-C4"

          format("% e", -109.52).should == "-1.095200e+02"
          format("% E", -109.52).should == "-1.095200E+02"
          format("% f", -10.952).should == "-10.952000"
          format("% g", -12.1234).should == "-12.1234"
          format("% G", -12.1234).should == "-12.1234"
          format("% a", -196).should == "-0x1.88p+7"
          format("% A", -196).should == "-0X1.88P+7"
        end

        it "prevents converting negative argument to two's complement form" do
          format("% b", -10).should == "-1010"
          format("% B", -10).should == "-1010"
          format("% o", -87).should == "-127"
          format("% x", -196).should == "-c4"
          format("% X", -196).should == "-C4"
        end

        it "treats several white spaces as one" do
          format("%     b", 10).should == " 1010"
          format("%     B", 10).should == " 1010"
          format("%     d", 112).should == " 112"
          format("%     i", 112).should == " 112"
          format("%     o", 87).should == " 127"
          format("%     u", 112).should == " 112"
          format("%     x", 196).should == " c4"
          format("%     X", 196).should == " C4"

          format("%     e", 109.52).should == " 1.095200e+02"
          format("%     E", 109.52).should == " 1.095200E+02"
          format("%     f", 10.952).should == " 10.952000"
          format("%     g", 12.1234).should == " 12.1234"
          format("%     G", 12.1234).should == " 12.1234"
          format("%     a", 196).should == " 0x1.88p+7"
          format("%     A", 196).should == " 0X1.88P+7"
        end
      end
    end

    describe "(digit)$" do
      it "specifies the absolute argument number for this field" do
        format("%2$b", 0, 10).should == "1010"
        format("%2$B", 0, 10).should == "1010"
        format("%2$d", 0, 112).should == "112"
        format("%2$i", 0, 112).should == "112"
        format("%2$o", 0, 87).should == "127"
        format("%2$u", 0, 112).should == "112"
        format("%2$x", 0, 196).should == "c4"
        format("%2$X", 0, 196).should == "C4"

        format("%2$e", 0, 109.52).should == "1.095200e+02"
        format("%2$E", 0, 109.52).should == "1.095200E+02"
        format("%2$f", 0, 10.952).should == "10.952000"
        format("%2$g", 0, 12.1234).should == "12.1234"
        format("%2$G", 0, 12.1234).should == "12.1234"
        format("%2$a", 0, 196).should == "0x1.88p+7"
        format("%2$A", 0, 196).should == "0X1.88P+7"

        format("%2$c", 1, 97).should == "a"
        format("%2$p", "a", []).should == "[]"
        format("%2$s", "-", "abc").should == "abc"
      end

      it "raises exception if argument number is bigger than actual arguments list" do
        -> () {
          format("%4$d", 1, 2, 3)
        }.should raise_error(ArgumentError)
      end

      it "ignores '-' sign" do
        format("%2$d", 1, 2, 3).should == "2"
        format("%-2$d", 1, 2, 3).should == "2"
      end

      it "raises ArgumentError exception when absolute and relative argument numbers are mixed" do
        -> () {
          format("%1$d %d", 1, 2)
        }.should raise_error(ArgumentError)
      end
    end

    describe "#" do
      context "applies to format o" do
        it "increases the precision until the first digit will be `0' if it is not formatted as complements" do
          format("%#o", 87).should == "0127"
        end

        it "does nothing for negative argument" do
          format("%#o", -87).should == "..7651"
        end
      end

      context "applies to formats bBxX" do
        it "prefixes the result with 0x, 0X, 0b and 0B respectively for non-zero argument" do
          format("%#b", 10).should == "0b1010"
          format("%#b", -10).should == "0b..10110"
          format("%#B", 10).should == "0B1010"
          format("%#B", -10).should == "0B..10110"

          format("%#x", 196).should == "0xc4"
          format("%#x", -196).should == "0x..f3c"
          format("%#X", 196).should == "0XC4"
          format("%#X", -196).should == "0X..F3C"
        end

        it "does nothing for zero argument" do
          format("%#b", 0).should == "0"
          format("%#B", 0).should == "0"

          format("%#o", 0).should == "0"

          format("%#x", 0).should == "0"
          format("%#X", 0).should == "0"
        end
      end

      context "applies to formats aAeEfgG" do
        it "forces a decimal point to be added, even if no digits follow" do
          format("%#.0a", 16.25).should == "0x1.p+4"
          format("%#.0A", 16.25).should == "0X1.P+4"

          format("%#.0e", 100).should == "1.e+02"
          format("%#.0E", 100).should == "1.E+02"

          format("%#.0f", 123.4).should == "123."

          format("%#g", 123456).should == "123456."
          format("%#G", 123456).should == "123456."
        end

        it "changes format from dd.dddd to exponential form for gG" do
          format("%#.0g", 123.4).should_not == "123."
          format("%#.0g", 123.4).should == "1.e+02"
        end
      end

      context "applies to gG" do
        it "does not remove trailing zeros" do
          format("%#g", 123.4).should == "123.400"
          format("%#g", 123.4).should == "123.400"
        end
      end
    end

    describe "+" do
      context "applies to numeric formats bBdiouxXaAeEfgG" do
        it "adds a leading plus sign to non-negative numbers" do
          format("%+b", 10).should == "+1010"
          format("%+B", 10).should == "+1010"
          format("%+d", 112).should == "+112"
          format("%+i", 112).should == "+112"
          format("%+o", 87).should == "+127"
          format("%+u", 112).should == "+112"
          format("%+x", 196).should == "+c4"
          format("%+X", 196).should == "+C4"

          format("%+e", 109.52).should == "+1.095200e+02"
          format("%+E", 109.52).should == "+1.095200E+02"
          format("%+f", 10.952).should == "+10.952000"
          format("%+g", 12.1234).should == "+12.1234"
          format("%+G", 12.1234).should == "+12.1234"
          format("%+a", 196).should == "+0x1.88p+7"
          format("%+A", 196).should == "+0X1.88P+7"
        end

        it "does not use two's complement form for negative numbers for formats bBoxX" do
          format("%+b", -10).should == "-1010"
          format("%+B", -10).should == "-1010"
          format("%+o", -87).should == "-127"
          format("%+x", -196).should == "-c4"
          format("%+X", -196).should == "-C4"
        end
      end
    end

    describe "-" do
      it "left-justifies the result of conversion if width is specified" do
        format("%-10b", 10).should == "1010      "
        format("%-10B", 10).should == "1010      "
        format("%-10d", 112).should == "112       "
        format("%-10i", 112).should == "112       "
        format("%-10o", 87).should == "127       "
        format("%-10u", 112).should == "112       "
        format("%-10x", 196).should == "c4        "
        format("%-10X", 196).should == "C4        "

        format("%-20e", 109.52).should == "1.095200e+02        "
        format("%-20E", 109.52).should == "1.095200E+02        "
        format("%-20f", 10.952).should == "10.952000           "
        format("%-20g", 12.1234).should == "12.1234             "
        format("%-20G", 12.1234).should == "12.1234             "
        format("%-20a", 196).should == "0x1.88p+7           "
        format("%-20A", 196).should == "0X1.88P+7           "

        format("%-10c", 97).should == "a         "
        format("%-10p", []).should == "[]        "
        format("%-10s", "abc").should == "abc       "
      end
    end

    describe "0 (zero)" do
      context "applies to numeric formats bBdiouxXaAeEfgG and width is specified" do
        it "pads with zeros, not spaces" do
          format("%010b", 10).should == "0000001010"
          format("%010B", 10).should == "0000001010"
          format("%010d", 112).should == "0000000112"
          format("%010i", 112).should == "0000000112"
          format("%010o", 87).should == "0000000127"
          format("%010u", 112).should == "0000000112"
          format("%010x", 196).should == "00000000c4"
          format("%010X", 196).should == "00000000C4"

          format("%020e", 109.52).should == "000000001.095200e+02"
          format("%020E", 109.52).should == "000000001.095200E+02"
          format("%020f", 10.952).should == "0000000000010.952000"
          format("%020g", 12.1234).should == "000000000000012.1234"
          format("%020G", 12.1234).should == "000000000000012.1234"
          format("%020a", 196).should == "0x000000000001.88p+7"
          format("%020A", 196).should == "0X000000000001.88P+7"
        end

        it "uses radix-1 when displays negative argument as a two's complement" do
          format("%010b", -10).should == "..11110110"
          format("%010B", -10).should == "..11110110"
          format("%010o", -87).should == "..77777651"
          format("%010x", -196).should == "..ffffff3c"
          format("%010X", -196).should == "..FFFFFF3C"
        end
      end
    end

    describe "*" do
      it "uses the previous argument as the field width" do
        format("%*b", 10, 10).should == "      1010"
        format("%*B", 10, 10).should == "      1010"
        format("%*d", 10, 112).should == "       112"
        format("%*i", 10, 112).should == "       112"
        format("%*o", 10, 87).should == "       127"
        format("%*u", 10, 112).should == "       112"
        format("%*x", 10, 196).should == "        c4"
        format("%*X", 10, 196).should == "        C4"

        format("%*e", 20, 109.52).should == "        1.095200e+02"
        format("%*E", 20, 109.52).should == "        1.095200E+02"
        format("%*f", 20, 10.952).should == "           10.952000"
        format("%*g", 20, 12.1234).should == "             12.1234"
        format("%*G", 20, 12.1234).should == "             12.1234"
        format("%*a", 20, 196).should == "           0x1.88p+7"
        format("%*A", 20, 196).should == "           0X1.88P+7"

        format("%*c", 10, 97).should == "         a"
        format("%*p", 10, []).should == "        []"
        format("%*s", 10, "abc").should == "       abc"
      end

      it "left-justifies the result if width is negative" do
        format("%*b", -10, 10).should == "1010      "
        format("%*B", -10, 10).should == "1010      "
        format("%*d", -10, 112).should == "112       "
        format("%*i", -10, 112).should == "112       "
        format("%*o", -10, 87).should == "127       "
        format("%*u", -10, 112).should == "112       "
        format("%*x", -10, 196).should == "c4        "
        format("%*X", -10, 196).should == "C4        "

        format("%*e", -20, 109.52).should == "1.095200e+02        "
        format("%*E", -20, 109.52).should == "1.095200E+02        "
        format("%*f", -20, 10.952).should == "10.952000           "
        format("%*g", -20, 12.1234).should == "12.1234             "
        format("%*G", -20, 12.1234).should == "12.1234             "
        format("%*a", -20, 196).should == "0x1.88p+7           "
        format("%*A", -20, 196).should == "0X1.88P+7           "

        format("%*c", -10, 97).should == "a         "
        format("%*p", -10, []).should == "[]        "
        format("%*s", -10, "abc").should == "abc       "
      end

      it "uses the specified argument as the width if * is followed by a number and $" do
        format("%1$*2$b", 10, 10).should == "      1010"
        format("%1$*2$B", 10, 10).should == "      1010"
        format("%1$*2$d", 112, 10).should == "       112"
        format("%1$*2$i", 112, 10).should == "       112"
        format("%1$*2$o", 87, 10).should == "       127"
        format("%1$*2$u", 112, 10).should == "       112"
        format("%1$*2$x", 196, 10).should == "        c4"
        format("%1$*2$X", 196, 10).should == "        C4"

        format("%1$*2$e", 109.52, 20).should == "        1.095200e+02"
        format("%1$*2$E", 109.52, 20).should == "        1.095200E+02"
        format("%1$*2$f", 10.952, 20).should == "           10.952000"
        format("%1$*2$g", 12.1234, 20).should == "             12.1234"
        format("%1$*2$G", 12.1234, 20).should == "             12.1234"
        format("%1$*2$a", 196, 20).should == "           0x1.88p+7"
        format("%1$*2$A", 196, 20).should == "           0X1.88P+7"

        format("%1$*2$c", 97, 10).should == "         a"
        format("%1$*2$p", [], 10).should == "        []"
        format("%1$*2$s", "abc", 10).should == "       abc"
      end

      it "left-justifies the result if specified with $ argument is negative" do
        format("%1$*2$b", 10, -10).should == "1010      "
        format("%1$*2$B", 10, -10).should == "1010      "
        format("%1$*2$d", 112, -10).should == "112       "
        format("%1$*2$i", 112, -10).should == "112       "
        format("%1$*2$o", 87, -10).should == "127       "
        format("%1$*2$u", 112, -10).should == "112       "
        format("%1$*2$x", 196, -10).should == "c4        "
        format("%1$*2$X", 196, -10).should == "C4        "

        format("%1$*2$e", 109.52, -20).should == "1.095200e+02        "
        format("%1$*2$E", 109.52, -20).should == "1.095200E+02        "
        format("%1$*2$f", 10.952, -20).should == "10.952000           "
        format("%1$*2$g", 12.1234, -20).should == "12.1234             "
        format("%1$*2$G", 12.1234, -20).should == "12.1234             "
        format("%1$*2$a", 196, -20).should == "0x1.88p+7           "
        format("%1$*2$A", 196, -20).should == "0X1.88P+7           "

        format("%1$*2$c", 97, -10).should == "a         "
        format("%1$*2$p", [], -10).should == "[]        "
        format("%1$*2$s", "abc", -10).should == "abc       "
      end

      it "raises ArgumentError when is mixed with width" do
        -> () {
          format("%*10d", 10, 112)
        }.should raise_error(ArgumentError)
      end
    end
  end

  describe "width" do
    it "specifies the minimum number of characters that will be written to the result" do
      format("%10b", 10).should == "      1010"
      format("%10B", 10).should == "      1010"
      format("%10d", 112).should == "       112"
      format("%10i", 112).should == "       112"
      format("%10o", 87).should == "       127"
      format("%10u", 112).should == "       112"
      format("%10x", 196).should == "        c4"
      format("%10X", 196).should == "        C4"

      format("%20e", 109.52).should == "        1.095200e+02"
      format("%20E", 109.52).should == "        1.095200E+02"
      format("%20f", 10.952).should == "           10.952000"
      format("%20g", 12.1234).should == "             12.1234"
      format("%20G", 12.1234).should == "             12.1234"
      format("%20a", 196).should == "           0x1.88p+7"
      format("%20A", 196).should == "           0X1.88P+7"

      format("%10c", 97).should == "         a"
      format("%10p", []).should == "        []"
      format("%10s", "abc").should == "       abc"
    end

    it "is ignored if argument's actual length is greater" do
      format("%5d", 1234567890).should == "1234567890"
    end
  end

  describe "precision" do
    context "integer types" do
      it "controls the number of decimal places displayed" do
        format("%.6b", 10).should == "001010"
        format("%.6B", 10).should == "001010"
        format("%.5d", 112).should == "00112"
        format("%.5i", 112).should == "00112"
        format("%.5o", 87).should == "00127"
        format("%.5u", 112).should == "00112"

        format("%.5x", 196).should == "000c4"
        format("%.5X", 196).should == "000C4"
      end
    end

    context "float types" do
      it "controls the number of decimal places displayed in fraction part" do
        format("%.10e", 109.52).should == "1.0952000000e+02"
        format("%.10E", 109.52).should == "1.0952000000E+02"
        format("%.10f", 10.952).should == "10.9520000000"
        format("%.10a", 196).should == "0x1.8800000000p+7"
        format("%.10A", 196).should == "0X1.8800000000P+7"
      end

      it "does not affect G format" do
        format("%.10g", 12.1234).should == "12.1234"
        format("%.10g", 123456789).should == "123456789"
      end
    end

    context "string formats" do
      it "determines the maximum number of characters to be copied from the string" do
        format("%.1p", [1]).should == "["
        format("%.2p", [1]).should == "[1"
        format("%.10p", [1]).should == "[1]"
        format("%.0p", [1]).should == ""

        format("%.1s", "abc").should == "a"
        format("%.2s", "abc").should == "ab"
        format("%.10s", "abc").should == "abc"
        format("%.0s", "abc").should == ""
      end
    end
  end

  describe "reference by name" do
    describe "%<name>s style" do
      it "uses value passed in a hash argument" do
        format("%<foo>d", foo: 123).should == "123"
      end

      it "supports flags, width, precision and type" do
        format("%+20.10<foo>f", foo: 10.952).should == "      +10.9520000000"
      end

      it "allows to place name in any position" do
        format("%+15.5<foo>f", foo: 10.952).should == "      +10.95200"
        format("%+15<foo>.5f", foo: 10.952).should == "      +10.95200"
        format("%+<foo>15.5f", foo: 10.952).should == "      +10.95200"
        format("%<foo>+15.5f", foo: 10.952).should == "      +10.95200"
      end

      it "cannot be mixed with unnamed style" do
        -> () {
          format("%d %<foo>d", 1, foo: "123")
        }.should raise_error(ArgumentError)
      end

      it "raises KeyError when there is no matching key" do
        -> () {
          format("%<foo>s", {})
        }.should raise_error(KeyError)
      end
    end

    describe "%{name} style" do
      it "uses value passed in a hash argument" do
        format("%{foo}", foo: 123).should == "123"
      end

      it "does not support type style" do
        format("%{foo}d", foo: 123).should == "123d"
      end

      it "supports flags, width and precision" do
        format("%-20.5{foo}", foo: "123456789").should == "12345               "
      end

      it "cannot be mixed with unnamed style" do
        -> () {
          format("%d %{foo}", 1, foo: "123")
        }.should raise_error(ArgumentError)
      end

      it "raises KeyError when there is no matching key" do
        -> () {
          format("%{foo}", {})
        }.should raise_error(KeyError)
      end

      it "converts value to String with to_s" do
        obj = Object.new
        def obj.to_s; end
        def obj.to_str; end

        obj.should_receive(:to_s).and_return("42")
        obj.should_not_receive(:to_str)

        format("%{foo}", foo: obj).should == "42"
      end
    end
  end
end
