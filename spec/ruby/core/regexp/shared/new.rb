# encoding: binary

describe :regexp_new, shared: true do
  it "requires one argument and creates a new regular expression object" do
    Regexp.send(@method, '').is_a?(Regexp).should == true
  end

  it "works by default for subclasses with overridden #initialize" do
    class RegexpSpecsSubclass < Regexp
      def initialize(*args)
        super
        @args = args
      end

      attr_accessor :args
    end

    class RegexpSpecsSubclassTwo < Regexp; end

    RegexpSpecsSubclass.send(@method, "hi").should be_kind_of(RegexpSpecsSubclass)
    RegexpSpecsSubclass.send(@method, "hi").args.first.should == "hi"

    RegexpSpecsSubclassTwo.send(@method, "hi").should be_kind_of(RegexpSpecsSubclassTwo)
  end
end

describe :regexp_new_non_string_or_regexp, shared: true do
  it "calls #to_str method for non-String/Regexp argument" do
    obj = Object.new
    def obj.to_str() "a" end

    Regexp.send(@method, obj).should == /a/
  end

  it "raises TypeError if there is no #to_str method for non-String/Regexp argument" do
    obj = Object.new
    -> { Regexp.send(@method, obj) }.should raise_error(TypeError, "no implicit conversion of Object into String")

    -> { Regexp.send(@method, 1) }.should raise_error(TypeError, "no implicit conversion of Integer into String")
    -> { Regexp.send(@method, 1.0) }.should raise_error(TypeError, "no implicit conversion of Float into String")
    -> { Regexp.send(@method, :symbol) }.should raise_error(TypeError, "no implicit conversion of Symbol into String")
    -> { Regexp.send(@method, []) }.should raise_error(TypeError, "no implicit conversion of Array into String")
  end

  it "raises TypeError if #to_str returns non-String value" do
    obj = Object.new
    def obj.to_str() [] end

    -> { Regexp.send(@method, obj) }.should raise_error(TypeError, /can't convert Object to String/)
  end
end

describe :regexp_new_string, shared: true do
  it "uses the String argument as an unescaped literal to construct a Regexp object" do
    Regexp.send(@method, "^hi{2,3}fo.o$").should == /^hi{2,3}fo.o$/
  end

  it "raises a RegexpError when passed an incorrect regexp" do
    -> { Regexp.send(@method, "^[$", 0) }.should raise_error(RegexpError, Regexp.new(Regexp.escape("premature end of char-class: /^[$/")))
  end

  it "does not set Regexp options if only given one argument" do
    r = Regexp.send(@method, 'Hi')
    (r.options & Regexp::IGNORECASE).should == 0
    (r.options & Regexp::MULTILINE).should == 0
    not_supported_on :opal do
      (r.options & Regexp::EXTENDED).should == 0
    end
  end

  it "does not set Regexp options if second argument is nil or false" do
    r = Regexp.send(@method, 'Hi', nil)
    (r.options & Regexp::IGNORECASE).should == 0
    (r.options & Regexp::MULTILINE).should == 0
    not_supported_on :opal do
      (r.options & Regexp::EXTENDED).should == 0
    end

    r = Regexp.send(@method, 'Hi', false)
    (r.options & Regexp::IGNORECASE).should == 0
    (r.options & Regexp::MULTILINE).should == 0
    not_supported_on :opal do
      (r.options & Regexp::EXTENDED).should == 0
    end
  end

  it "sets options from second argument if it is true" do
    r = Regexp.send(@method, 'Hi', true)
    (r.options & Regexp::IGNORECASE).should_not == 0
    (r.options & Regexp::MULTILINE).should == 0
    not_supported_on :opal do
      (r.options & Regexp::EXTENDED).should == 0
    end
  end

  it "sets options from second argument if it is one of the Integer option constants" do
    r = Regexp.send(@method, 'Hi', Regexp::IGNORECASE)
    (r.options & Regexp::IGNORECASE).should_not == 0
    (r.options & Regexp::MULTILINE).should == 0
    not_supported_on :opal do
      (r.options & Regexp::EXTENDED).should == 0
    end

    r = Regexp.send(@method, 'Hi', Regexp::MULTILINE)
    (r.options & Regexp::IGNORECASE).should == 0
    (r.options & Regexp::MULTILINE).should_not == 0
    not_supported_on :opal do
      (r.options & Regexp::EXTENDED).should == 0
    end

    not_supported_on :opal do
      r = Regexp.send(@method, 'Hi', Regexp::EXTENDED)
      (r.options & Regexp::IGNORECASE).should == 0
      (r.options & Regexp::MULTILINE).should == 0
      (r.options & Regexp::EXTENDED).should_not == 1
    end
  end

  it "accepts an Integer of two or more options ORed together as the second argument" do
    r = Regexp.send(@method, 'Hi', Regexp::IGNORECASE | Regexp::EXTENDED)
    (r.options & Regexp::IGNORECASE).should_not == 0
    (r.options & Regexp::MULTILINE).should == 0
    (r.options & Regexp::EXTENDED).should_not == 0
  end

  it "does not try to convert the second argument to Integer with #to_int method call" do
    ScratchPad.clear
    obj = Object.new
    def obj.to_int() ScratchPad.record(:called) end

    -> {
      Regexp.send(@method, "Hi", obj)
    }.should complain(/expected true or false as ignorecase/, {verbose: true})

    ScratchPad.recorded.should == nil
  end

  it "warns any non-Integer, non-nil, non-false second argument" do
    r = nil
    -> {
      r = Regexp.send(@method, 'Hi', Object.new)
    }.should complain(/expected true or false as ignorecase/, {verbose: true})
    (r.options & Regexp::IGNORECASE).should_not == 0
    (r.options & Regexp::MULTILINE).should == 0
    not_supported_on :opal do
      (r.options & Regexp::EXTENDED).should == 0
    end
  end

  it "accepts a String of supported flags as the second argument" do
    r = Regexp.send(@method, 'Hi', 'i')
    (r.options & Regexp::IGNORECASE).should_not == 0
    (r.options & Regexp::MULTILINE).should == 0
    not_supported_on :opal do
      (r.options & Regexp::EXTENDED).should == 0
    end

    r = Regexp.send(@method, 'Hi', 'imx')
    (r.options & Regexp::IGNORECASE).should_not == 0
    (r.options & Regexp::MULTILINE).should_not == 0
    not_supported_on :opal do
      (r.options & Regexp::EXTENDED).should_not == 0
    end

    r = Regexp.send(@method, 'Hi', 'mimi')
    (r.options & Regexp::IGNORECASE).should_not == 0
    (r.options & Regexp::MULTILINE).should_not == 0
    not_supported_on :opal do
      (r.options & Regexp::EXTENDED).should == 0
    end

    r = Regexp.send(@method, 'Hi', '')
    (r.options & Regexp::IGNORECASE).should == 0
    (r.options & Regexp::MULTILINE).should == 0
    not_supported_on :opal do
      (r.options & Regexp::EXTENDED).should == 0
    end
  end

  it "raises an Argument error if the second argument contains unsupported chars" do
    -> { Regexp.send(@method, 'Hi', 'e') }.should raise_error(ArgumentError, "unknown regexp option: e")
    -> { Regexp.send(@method, 'Hi', 'n') }.should raise_error(ArgumentError, "unknown regexp option: n")
    -> { Regexp.send(@method, 'Hi', 's') }.should raise_error(ArgumentError, "unknown regexp option: s")
    -> { Regexp.send(@method, 'Hi', 'u') }.should raise_error(ArgumentError, "unknown regexp option: u")
    -> { Regexp.send(@method, 'Hi', 'j') }.should raise_error(ArgumentError, "unknown regexp option: j")
    -> { Regexp.send(@method, 'Hi', 'mjx') }.should raise_error(ArgumentError, /unknown regexp option: mjx\b/)
  end

  describe "with escaped characters" do
    it "raises a Regexp error if there is a trailing backslash" do
      -> { Regexp.send(@method, "\\") }.should raise_error(RegexpError, Regexp.new(Regexp.escape("too short escape sequence: /\\/")))
    end

    it "does not raise a Regexp error if there is an escaped trailing backslash" do
      -> { Regexp.send(@method, "\\\\") }.should_not raise_error(RegexpError)
    end

    it "accepts a backspace followed by a non-special character" do
      Regexp.send(@method, "\\N").should == /#{"\x5c"+"N"}/
    end

    it "raises a RegexpError if \\x is not followed by any hexadecimal digits" do
      -> { Regexp.send(@method, "\\" + "xn") }.should raise_error(RegexpError, Regexp.new(Regexp.escape("invalid hex escape: /\\xn/")))
    end

    it "raises a RegexpError if less than four digits are given for \\uHHHH" do
      -> { Regexp.send(@method, "\\" + "u304") }.should raise_error(RegexpError, Regexp.new(Regexp.escape("invalid Unicode escape: /\\u304/")))
    end

    it "raises a RegexpError if the \\u{} escape is empty" do
      -> { Regexp.send(@method, "\\" + "u{}") }.should raise_error(RegexpError, Regexp.new(Regexp.escape("invalid Unicode list: /\\u{}/")))
    end

    it "raises a RegexpError if the \\u{} escape contains non hexadecimal digits" do
      -> { Regexp.send(@method, "\\" + "u{abcX}") }.should raise_error(RegexpError, Regexp.new(Regexp.escape("invalid Unicode list: /\\u{abcX}/")))
    end

    it "raises a RegexpError if more than six hexadecimal digits are given" do
      -> { Regexp.send(@method, "\\" + "u{0ffffff}") }.should raise_error(RegexpError, Regexp.new(Regexp.escape("invalid Unicode range: /\\u{0ffffff}/")))
    end

    it "returns a Regexp with US-ASCII encoding if only 7-bit ASCII characters are present regardless of the input String's encoding" do
      Regexp.send(@method, "abc").encoding.should == Encoding::US_ASCII
    end

    it "returns a Regexp with source String having US-ASCII encoding if only 7-bit ASCII characters are present regardless of the input String's encoding" do
      Regexp.send(@method, "abc").source.encoding.should == Encoding::US_ASCII
    end

    it "returns a Regexp with US-ASCII encoding if UTF-8 escape sequences using only 7-bit ASCII are present" do
      Regexp.send(@method, "\u{61}").encoding.should == Encoding::US_ASCII
    end

    it "returns a Regexp with source String having US-ASCII encoding if UTF-8 escape sequences using only 7-bit ASCII are present" do
      Regexp.send(@method, "\u{61}").source.encoding.should == Encoding::US_ASCII
    end

    it "returns a Regexp with UTF-8 encoding if any UTF-8 escape sequences outside 7-bit ASCII are present" do
      Regexp.send(@method, "\u{ff}").encoding.should == Encoding::UTF_8
    end

    it "returns a Regexp with source String having UTF-8 encoding if any UTF-8 escape sequences outside 7-bit ASCII are present" do
      Regexp.send(@method, "\u{ff}").source.encoding.should == Encoding::UTF_8
    end

    it "returns a Regexp with the input String's encoding" do
      str = "\x82\xa0".dup.force_encoding(Encoding::Shift_JIS)
      Regexp.send(@method, str).encoding.should == Encoding::Shift_JIS
    end

    it "returns a Regexp with source String having the input String's encoding" do
      str = "\x82\xa0".dup.force_encoding(Encoding::Shift_JIS)
      Regexp.send(@method, str).source.encoding.should == Encoding::Shift_JIS
    end
  end
end

describe :regexp_new_string_binary, shared: true do
  describe "with escaped characters" do
  end
end

describe :regexp_new_regexp, shared: true do
  it "uses the argument as a literal to construct a Regexp object" do
    Regexp.send(@method, /^hi{2,3}fo.o$/).should == /^hi{2,3}fo.o$/
  end

  it "preserves any options given in the Regexp literal" do
    (Regexp.send(@method, /Hi/i).options & Regexp::IGNORECASE).should_not == 0
    (Regexp.send(@method, /Hi/m).options & Regexp::MULTILINE).should_not == 0
    not_supported_on :opal do
      (Regexp.send(@method, /Hi/x).options & Regexp::EXTENDED).should_not == 0
    end

    not_supported_on :opal do
      r = Regexp.send @method, /Hi/imx
      (r.options & Regexp::IGNORECASE).should_not == 0
      (r.options & Regexp::MULTILINE).should_not == 0
      (r.options & Regexp::EXTENDED).should_not == 0
    end

    r = Regexp.send @method, /Hi/
    (r.options & Regexp::IGNORECASE).should == 0
    (r.options & Regexp::MULTILINE).should == 0
    not_supported_on :opal do
      (r.options & Regexp::EXTENDED).should == 0
    end
  end

  it "does not honour options given as additional arguments" do
    r = nil
    -> {
      r = Regexp.send @method, /hi/, Regexp::IGNORECASE
    }.should complain(/flags ignored/)
    (r.options & Regexp::IGNORECASE).should == 0
  end

  not_supported_on :opal do
    it "sets the encoding to UTF-8 if the Regexp literal has the 'u' option" do
      Regexp.send(@method, /Hi/u).encoding.should == Encoding::UTF_8
    end

    it "sets the encoding to EUC-JP if the Regexp literal has the 'e' option" do
      Regexp.send(@method, /Hi/e).encoding.should == Encoding::EUC_JP
    end

    it "sets the encoding to Windows-31J if the Regexp literal has the 's' option" do
      Regexp.send(@method, /Hi/s).encoding.should == Encoding::Windows_31J
    end

    it "sets the encoding to US-ASCII if the Regexp literal has the 'n' option and the source String is ASCII only" do
      Regexp.send(@method, /Hi/n).encoding.should == Encoding::US_ASCII
    end
  end
end
