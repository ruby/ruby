require_relative '../../spec_helper'

describe "Float#to_s" do
  it "returns 'NaN' for NaN" do
    nan_value().to_s.should == 'NaN'
  end

  it "returns 'Infinity' for positive infinity" do
    infinity_value().to_s.should == 'Infinity'
  end

  it "returns '-Infinity' for negative infinity" do
    (-infinity_value()).to_s.should == '-Infinity'
  end

  it "returns '0.0' for 0.0" do
    0.0.to_s.should == "0.0"
  end

  platform_is_not :openbsd do
    it "emits '-' for -0.0" do
      -0.0.to_s.should == "-0.0"
    end
  end

  it "emits a '-' for negative values" do
    -3.14.to_s.should == "-3.14"
  end

  it "emits a trailing '.0' for a whole number" do
    50.0.to_s.should == "50.0"
  end

  it "emits a trailing '.0' for the mantissa in e format" do
    1.0e20.to_s.should == "1.0e+20"
  end

  it "uses non-e format for a positive value with fractional part having 5 significant figures" do
    0.0001.to_s.should == "0.0001"
  end

  it "uses non-e format for a negative value with fractional part having 5 significant figures" do
    -0.0001.to_s.should == "-0.0001"
  end

  it "uses e format for a positive value with fractional part having 6 significant figures" do
    0.00001.to_s.should == "1.0e-05"
  end

  it "uses e format for a negative value with fractional part having 6 significant figures" do
    -0.00001.to_s.should == "-1.0e-05"
  end

  it "uses non-e format for a positive value with whole part having 15 significant figures" do
    10000000000000.0.to_s.should == "10000000000000.0"
  end

  it "uses non-e format for a negative value with whole part having 15 significant figures" do
    -10000000000000.0.to_s.should == "-10000000000000.0"
  end

  it "uses non-e format for a positive value with whole part having 16 significant figures" do
    100000000000000.0.to_s.should == "100000000000000.0"
  end

  it "uses non-e format for a negative value with whole part having 16 significant figures" do
    -100000000000000.0.to_s.should == "-100000000000000.0"
  end

  it "uses e format for a positive value with whole part having 18 significant figures" do
    10000000000000000.0.to_s.should == "1.0e+16"
  end

  it "uses e format for a negative value with whole part having 18 significant figures" do
    -10000000000000000.0.to_s.should == "-1.0e+16"
  end

  it "uses e format for a positive value with whole part having 17 significant figures" do
    1000000000000000.0.to_s.should == "1.0e+15"
  end

  it "uses e format for a negative value with whole part having 17 significant figures" do
    -1000000000000000.0.to_s.should == "-1.0e+15"
  end

  # #3273
  it "outputs the minimal, unique form necessary to recreate the value" do
    value = 0.21611564636388508
    string = "0.21611564636388508"

    value.to_s.should == string
    string.to_f.should == value
  end

  it "outputs the minimal, unique form to represent the value" do
    0.56.to_s.should == "0.56"
  end

  describe "matches" do
    ruby_version_is "2.4" do # For unpack1
      it "random examples in all ranges" do
        # 50.times do
        #   bytes = (0...8).map { rand(256) }
        #   string = bytes.pack('C8')
        #   float = string.unpack('D').first
        #   puts "      #{bytes.pack('C8').inspect}.unpack1('D').to_s.should == #{float.to_s.inspect}"
        # end

        "\x97\x15\xC1| \xF5\x19\xAD".unpack1('D').to_s.should == "-1.9910613439044092e-91"
        "\xBF\xF0\x14\xAD\xDF\x17q\xD1".unpack1('D').to_s.should == "-2.075408637901046e+84"
        "\xDF\xBD\xC0\x89\xDA\x1F&$".unpack1('D').to_s.should == "1.5219626883645564e-134"
        "|0<?a\xFB\xBFG".unpack1('D').to_s.should == "4.251130678455814e+37"
        "U\xEE*\xB7\xF1\xB8\xE7\x18".unpack1('D').to_s.should == "1.0648588700899858e-188"
        "\x15Y\xD1J\x80/7\xD0".unpack1('D').to_s.should == "-2.6847034291392176e+78"
        "\x1D\x1E\xD2\x9A3)\xF5q".unpack1('D').to_s.should == "8.818842365424256e+240"
        "M\xD0C\xA3\x19-\xE3\xE5".unpack1('D').to_s.should == "-6.365746090981858e+182"
        "\xAFf\xFE\xF0$\x85\x01L".unpack1('D').to_s.should == "1.374692728674642e+58"
        "'N\xB7\x12\xE0\xC8t\t".unpack1('D').to_s.should == "4.1254080603298014e-263"
        "\xAFn\xF2x\x85\xB5\x15j".unpack1('D').to_s.should == "1.0635019031720867e+203"
        "nQ\x95\xFA\xD9\xE3\xC5)".unpack1('D').to_s.should == "1.8641386367625094e-107"
        "\xC2\x9A\xB1|/\xCAJM".unpack1('D').to_s.should == "2.204135837758401e+64"
        "q n\xD8\x86\xF2\xA8D".unpack1('D').to_s.should == "5.890531214599543e+22"
        "dmR\xC6\xB3\xF3\x95G".unpack1('D').to_s.should == "7.294790578028111e+36"
        "6I\x0E)?E\xB5\xE1".unpack1('D').to_s.should == "-4.7847061687992665e+162"
        "\xCD\xE0\xBBy\x9F\xD8\xE89".unpack1('D').to_s.should == "9.800091365433584e-30"
        "\xB8\x98TN\x98\xEE\xC1\xF9".unpack1('D').to_s.should == "-3.178740061599073e+278"
        "\x8F_\xFF\x15\x1F2\x17B".unpack1('D').to_s.should == "24906286463.84332"
        "\x94\x18V\xC5&\xE6\xEAi".unpack1('D').to_s.should == "1.6471900588998988e+202"
        "\xECq\xB1\x01\ai\xBD,".unpack1('D').to_s.should == "3.5248469410018065e-93"
        "\x9C\xC6\x13pG\xDAx\x9A".unpack1('D').to_s.should == "-3.743306318201459e-181"
        "\xEA7,gJ\xEE\x8E*".unpack1('D').to_s.should == "1.0789044330549825e-103"
        "1\xD3\xF5K\x8D\xEF\xA7\r".unpack1('D').to_s.should == "7.011009309284311e-243"
        "o\xB3\x02\xAF\x9D\xFC\r\xF6".unpack1('D').to_s.should == "-4.610585875652112e+260"
        "&:x\x15\xFC3P\x01".unpack1('D').to_s.should == "2.362770515774595e-302"
        "\xE6<C\xB8\x90\xF2\xCF\x90".unpack1('D').to_s.should == "-1.0535871178808475e-227"
        "\x9Al\aB6's}".unpack1('D').to_s.should == "1.957205609213647e+296"
        "+\v\x16\xFD\x19\x0E\x9B\x06".unpack1('D').to_s.should == "7.631200870990123e-277"
        "\xEC\xF8~\xDA\xE7Tf\x92".unpack1('D').to_s.should == "-4.942358450191624e-220"
        "\xE0\xA0\xC9\x906\xBDcI".unpack1('D').to_s.should == "3.521575588133954e+45"
        "\xBD\xFD\xC9\xFD\rp\x02\x0F".unpack1('D').to_s.should == "2.2651682962118346e-236"
        "\xE9\xA8\xAD\xC4\xF6u\xF7\x19".unpack1('D').to_s.should == "1.3803378872547194e-183"
        "\"f\xED9\x17\xF0\xF1!".unpack1('D').to_s.should == "3.591307506787987e-145"
        "\xE6\xF2\xB6\x9CFl\xB3O".unpack1('D').to_s.should == "8.785250953340842e+75"
        "g\xFD\xEA\r~x\xBA\x9D".unpack1('D').to_s.should == "-1.7955908504285607e-165"
        "\xE2\x84J\xC7\x00\n/\x06".unpack1('D').to_s.should == "6.839790344291208e-279"
        "s\xFB\xA58x\xF1\xA9\xD9".unpack1('D').to_s.should == "-8.574967051032431e+123"
        "\xE2\x9D\xBE\xE2\x10k{\xFC".unpack1('D').to_s.should == "-4.2751876153404507e+291"
        "!z \xB4i4\x8C5".unpack1('D').to_s.should == "9.423078517655126e-51"
        "!_\xEAp- 7R".unpack1('D').to_s.should == "1.1500944673871687e+88"
        "\x03\xAD=\\\xCB >\xBB".unpack1('D').to_s.should == "-2.4921382721208654e-23"
        "\x94\x01\xB1\x87\x10\x9B#\x88".unpack1('D').to_s.should == "-1.8555672851958583e-269"
        "\x90H\xFF\\S\x01)\x89".unpack1('D').to_s.should == "-1.5509713490195968e-264"
        "HW@\x13\x85&=)".unpack1('D').to_s.should == "4.848496966571536e-110"
        "\x14\xDB\\\x10\x93\x9C\xD66".unpack1('D').to_s.should == "1.5842813502410472e-44"
        "\x9D8p>\xFF\x9B[\xF3".unpack1('D').to_s.should == "-4.826061446912647e+247"
        "c\x9D}\t]\xF9pg".unpack1('D').to_s.should == "1.8907034486212682e+190"
        "\xA51\xC9WJ\xB5a^".unpack1('D').to_s.should == "4.422435231445608e+146"
        "\x8BL\x90\xCB\xEARf\f".unpack1('D').to_s.should == "6.235963569982745e-249"
      end

      it "random examples in human ranges" do
        # 50.times do
        #   formatted = ''
        #   rand(1..3).times do
        #     formatted << rand(10).to_s
        #   end
        #   formatted << '.'
        #   rand(1..9).times do
        #     formatted << rand(10).to_s
        #   end
        #   float = formatted.to_f
        #   string = [float].pack('D')
        #   puts "      #{string.inspect}.unpack1('D').to_s.should == #{float.to_s.inspect}"
        # end

        ";\x01M\x84\r\xF7M@".unpack1('D').to_s.should == "59.9301"
        "\xAE\xD3HKe|\x8A@".unpack1('D').to_s.should == "847.54946"
        "/\xDD$\x06\x81u8@".unpack1('D').to_s.should == "24.459"
        "E\xD8\xF0\xF4JY\xF0?".unpack1('D').to_s.should == "1.0218"
        "[\brP\xC2\xCC\x05@".unpack1('D').to_s.should == "2.72498"
        "\xE6w\x9A\xCCx\xF6T@".unpack1('D').to_s.should == "83.851123"
        "\xB4\xD4&\xC0C\xFD.@".unpack1('D').to_s.should == "15.494657521"
        "\xCD\xCC\xCC\xCC\xCCLM@".unpack1('D').to_s.should == "58.6"
        "\xA1\x84\x99\xB6\x7F\xE5\x13@".unpack1('D').to_s.should == "4.97412"
        "\xD7\xA3p=\n\x9C\x80@".unpack1('D').to_s.should == "531.505"
        "S\x96!\x8E\xF5\x0E\x8F@".unpack1('D').to_s.should == "993.8699"
        "\xF1F\xE6\x91?\x18\xD7?".unpack1('D').to_s.should == "0.360855"
        "=\n\xD7\xA3p=\x15@".unpack1('D').to_s.should == "5.31"
        "\x90Ci\x147\xC74@".unpack1('D').to_s.should == "20.7781842"
        "A\ft\xED\v\xE8\xB9?".unpack1('D').to_s.should == "0.101197"
        "\x9A\x99\x99\x99\x999T@".unpack1('D').to_s.should == "80.9"
        "\x00\x00\x00\x00\x00\x00\x1A@".unpack1('D').to_s.should == "6.5"
        "\xD3J\xC6\xD6\x98\x8Es@".unpack1('D').to_s.should == "312.9123142"
        "SQ\xE5I\fQ\x1E@".unpack1('D').to_s.should == "7.57914844"
        "k]Q\xE7\xDDb\x1E@".unpack1('D').to_s.should == "7.59654962"
        "\x1F\x85\xEBQ\xB8\xEAz@".unpack1('D').to_s.should == "430.67"
        "\x00\x00\x00\x00\x00\x00\x14@".unpack1('D').to_s.should == "5.0"
        "{\x14\xAEG\xE1\n}@".unpack1('D').to_s.should == "464.68"
        "\x12\x83\xC0\xCA\xA1=V@".unpack1('D').to_s.should == "88.963"
        "\x9Aw\x9C\xA2#y\e@".unpack1('D').to_s.should == "6.8683"
        "(\x0F\v\xB5\xA6y\xFB?".unpack1('D').to_s.should == "1.7172"
        "\xD5x\xE9&1H!@".unpack1('D').to_s.should == "8.641"
        "w'Deh\x1Ab@".unpack1('D').to_s.should == "144.8252436"
        ":X\xFF\xE70_\x04@".unpack1('D').to_s.should == "2.54648"
        "E4\xB2\x12\x90\xCA\x1E@".unpack1('D').to_s.should == "7.69781522"
        "fffff\xAA\x80@".unpack1('D').to_s.should == "533.3"
        "\xCD\x92\x005\xB5p:@".unpack1('D').to_s.should == "26.440265"
        "\xBE\x1D<nS\x7F\x19@".unpack1('D').to_s.should == "6.3743417"
        "R\xB8\x1E\x85\xEBYb@".unpack1('D').to_s.should == "146.81"
        "\x02\x87\xAB^\xD9\xC0\xF4?".unpack1('D').to_s.should == "1.2970823"
        "\x00\x00\x00\x00\x00\x00\"@".unpack1('D').to_s.should == "9.0"
        "Zd;\xDFO3\x84@".unpack1('D').to_s.should == "646.414"
        "\x9A\x99\x99\x99\x99\x99\t@".unpack1('D').to_s.should == "3.2"
        "\xCD#\x7F0\xF0\xE5i@".unpack1('D').to_s.should == "207.18557"
        "\xBE\x9F\x1A/\xDD$\xF2?".unpack1('D').to_s.should == "1.134"
        "\xEE|?5^\xBA\xF3?".unpack1('D').to_s.should == "1.233"
        "\xB4\xB7\xFE\xD7\x05\x03i@".unpack1('D').to_s.should == "200.094463346"
        "N\x95\xD6|\xE8HG@".unpack1('D').to_s.should == "46.56959496"
        "Y\x868\xD6\xC5-!@".unpack1('D').to_s.should == "8.5894"
        "myE\xED\a;\x12@".unpack1('D').to_s.should == "4.557647426"
        "\xA7s\xEAo\xAE\x96B@".unpack1('D').to_s.should == "37.1771984"
        "\x14\x7Fo.\x99\x11|@".unpack1('D').to_s.should == "449.0998978"
        "\xB2\x9EZ}u\x89;@".unpack1('D').to_s.should == "27.536949"
        "\xD7\xA3p=\nwY@".unpack1('D').to_s.should == "101.86"
        "\xF3\xE6p\xAD\xF6\xC3x@".unpack1('D').to_s.should == "396.247724"
      end
    end

    it "random values from divisions" do
      (1.0 / 7).to_s.should == "0.14285714285714285"

      # 50.times do
      #    a = rand(10)
      #    b = rand(10)
      #    c = rand(10)
      #    d = rand(10)
      #    expression = "#{a}.#{b} / #{c}.#{d}"
      #    puts "      (#{expression}).to_s.should == #{eval(expression).to_s.inspect}"
      #  end

      (1.1 / 7.1).to_s.should == "0.15492957746478875"
      (6.5 / 8.8).to_s.should == "0.7386363636363635"
      (4.8 / 4.3).to_s.should == "1.1162790697674418"
      (4.0 / 1.9).to_s.should == "2.1052631578947367"
      (9.1 / 0.8).to_s.should == "11.374999999999998"
      (5.3 / 7.5).to_s.should == "0.7066666666666667"
      (2.8 / 1.8).to_s.should == "1.5555555555555554"
      (2.1 / 2.5).to_s.should == "0.8400000000000001"
      (3.5 / 6.0).to_s.should == "0.5833333333333334"
      (4.6 / 0.3).to_s.should == "15.333333333333332"
      (0.6 / 2.4).to_s.should == "0.25"
      (1.3 / 9.1).to_s.should == "0.14285714285714288"
      (0.3 / 5.0).to_s.should == "0.06"
      (5.0 / 4.2).to_s.should == "1.1904761904761905"
      (3.0 / 2.0).to_s.should == "1.5"
      (6.3 / 2.0).to_s.should == "3.15"
      (5.4 / 6.0).to_s.should == "0.9"
      (9.6 / 8.1).to_s.should == "1.1851851851851851"
      (8.7 / 1.6).to_s.should == "5.437499999999999"
      (1.9 / 7.8).to_s.should == "0.24358974358974358"
      (0.5 / 2.1).to_s.should == "0.23809523809523808"
      (9.3 / 5.8).to_s.should == "1.6034482758620692"
      (2.7 / 8.0).to_s.should == "0.3375"
      (9.7 / 7.8).to_s.should == "1.2435897435897436"
      (8.1 / 2.4).to_s.should == "3.375"
      (7.7 / 2.7).to_s.should == "2.8518518518518516"
      (7.9 / 1.7).to_s.should == "4.647058823529412"
      (6.5 / 8.2).to_s.should == "0.7926829268292683"
      (7.8 / 9.6).to_s.should == "0.8125"
      (2.2 / 4.6).to_s.should == "0.47826086956521746"
      (0.0 / 1.0).to_s.should == "0.0"
      (8.3 / 2.9).to_s.should == "2.8620689655172415"
      (3.1 / 6.1).to_s.should == "0.5081967213114754"
      (2.8 / 7.8).to_s.should == "0.358974358974359"
      (8.0 / 0.1).to_s.should == "80.0"
      (1.7 / 6.4).to_s.should == "0.265625"
      (1.8 / 5.4).to_s.should == "0.3333333333333333"
      (8.0 / 5.8).to_s.should == "1.3793103448275863"
      (5.2 / 4.1).to_s.should == "1.2682926829268295"
      (9.8 / 5.8).to_s.should == "1.6896551724137934"
      (5.4 / 9.5).to_s.should == "0.5684210526315789"
      (8.4 / 4.9).to_s.should == "1.7142857142857142"
      (1.7 / 3.5).to_s.should == "0.4857142857142857"
      (1.2 / 5.1).to_s.should == "0.23529411764705882"
      (1.4 / 2.0).to_s.should == "0.7"
      (4.8 / 8.0).to_s.should == "0.6"
      (9.0 / 2.5).to_s.should == "3.6"
      (0.2 / 0.6).to_s.should == "0.33333333333333337"
      (7.8 / 5.2).to_s.should == "1.5"
      (9.5 / 5.5).to_s.should == "1.7272727272727273"
    end
  end
end

with_feature :encoding do
  describe "Float#to_s" do
    before :each do
      @internal = Encoding.default_internal
    end

    after :each do
      Encoding.default_internal = @internal
    end

    it "returns a String in US-ASCII encoding when Encoding.default_internal is nil" do
      Encoding.default_internal = nil
      1.23.to_s.encoding.should equal(Encoding::US_ASCII)
    end

    it "returns a String in US-ASCII encoding when Encoding.default_internal is not nil" do
      Encoding.default_internal = Encoding::IBM437
      5.47.to_s.encoding.should equal(Encoding::US_ASCII)
    end
  end
end
