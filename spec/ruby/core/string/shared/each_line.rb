describe :string_each_line, shared: true do
  it "splits using default newline separator when none is specified" do
    a = []
    "one\ntwo\r\nthree".send(@method) { |s| a << s }
    a.should == ["one\n", "two\r\n", "three"]

    b = []
    "hello\n\n\nworld".send(@method) { |s| b << s }
    b.should == ["hello\n", "\n", "\n", "world"]

    c = []
    "\n\n\n\n\n".send(@method) {|s| c << s}
    c.should == ["\n", "\n", "\n", "\n", "\n"]
  end

  it "splits self using the supplied record separator and passes each substring to the block" do
    a = []
    "one\ntwo\r\nthree".send(@method, "\n") { |s| a << s }
    a.should == ["one\n", "two\r\n", "three"]

    b = []
    "hello\nworld".send(@method, 'l') { |s| b << s }
    b.should == [ "hel", "l", "o\nworl", "d" ]

    c = []
    "hello\n\n\nworld".send(@method, "\n") { |s| c << s }
    c.should == ["hello\n", "\n", "\n", "world"]
  end

  it "splits strings containing multibyte characters" do
    s = <<~EOS
      foo
      🤡🤡🤡🤡🤡🤡🤡
      bar
      baz
    EOS

    b = []
    s.send(@method) { |part| b << part }
    b.should == ["foo\n", "🤡🤡🤡🤡🤡🤡🤡\n", "bar\n", "baz\n"]
  end

  ruby_version_is ''...'2.7' do
    it "taints substrings that are passed to the block if self is tainted" do
      "one\ntwo\r\nthree".taint.send(@method) { |s| s.should.tainted? }

      "x.y.".send(@method, ".".taint) { |s| s.should_not.tainted? }
    end
  end

  it "passes self as a whole to the block if the separator is nil" do
    a = []
    "one\ntwo\r\nthree".send(@method, nil) { |s| a << s }
    a.should == ["one\ntwo\r\nthree"]
  end

  it "yields paragraphs (broken by 2 or more successive newlines) when passed '' and replaces multiple newlines with only two ones" do
    a = []
    "hello\nworld\n\n\nand\nuniverse\n\n\n\n\n".send(@method, '') { |s| a << s }
    a.should == ["hello\nworld\n\n", "and\nuniverse\n\n"]

    a = []
    "hello\nworld\n\n\nand\nuniverse\n\n\n\n\ndog".send(@method, '') { |s| a << s }
    a.should == ["hello\nworld\n\n", "and\nuniverse\n\n", "dog"]
  end

  describe "uses $/" do
    before :each do
      @before_separator = $/
    end

    after :each do
      suppress_warning {$/ = @before_separator}
    end

    it "as the separator when none is given" do
      [
        "", "x", "x\ny", "x\ry", "x\r\ny", "x\n\r\r\ny",
        "hello hullo bello"
      ].each do |str|
        ["", "llo", "\n", "\r", nil].each do |sep|
          expected = []
          str.send(@method, sep) { |x| expected << x }

          suppress_warning {$/ = sep}

          actual = []
          suppress_warning {str.send(@method) { |x| actual << x }}

          actual.should == expected
        end
      end
    end
  end

  ruby_version_is ''...'3.0' do
    it "yields subclass instances for subclasses" do
      a = []
      StringSpecs::MyString.new("hello\nworld").send(@method) { |s| a << s.class }
      a.should == [StringSpecs::MyString, StringSpecs::MyString]
    end
  end

  ruby_version_is '3.0' do
    it "yields String instances for subclasses" do
      a = []
      StringSpecs::MyString.new("hello\nworld").send(@method) { |s| a << s.class }
      a.should == [String, String]
    end
  end

  it "returns self" do
    s = "hello\nworld"
    (s.send(@method) {}).should equal(s)
  end

  it "tries to convert the separator to a string using to_str" do
    separator = mock('l')
    separator.should_receive(:to_str).and_return("l")

    a = []
    "hello\nworld".send(@method, separator) { |s| a << s }
    a.should == [ "hel", "l", "o\nworl", "d" ]
  end

  it "does not care if the string is modified while substituting" do
    str = "hello\nworld."
    out = []
    str.send(@method){|x| out << x; str[-1] = '!' }.should == "hello\nworld!"
    out.should == ["hello\n", "world."]
  end

  it "raises a TypeError when the separator can't be converted to a string" do
    -> { "hello world".send(@method, false) {}     }.should raise_error(TypeError)
    -> { "hello world".send(@method, mock('x')) {} }.should raise_error(TypeError)
  end

  it "accepts a string separator" do
    "hello world".send(@method, ?o).to_a.should == ["hello", " wo", "rld"]
  end

  it "raises a TypeError when the separator is a symbol" do
    -> { "hello world".send(@method, :o).to_a }.should raise_error(TypeError)
  end

  context "when `chomp` keyword argument is passed" do
    it "removes new line characters when separator is not specified" do
      a = []
      "hello \nworld\n".send(@method, chomp: true) { |s| a << s }
      a.should == ["hello ", "world"]

      a = []
      "hello \r\nworld\r\n".send(@method, chomp: true) { |s| a << s }
      a.should == ["hello ", "world"]
    end

    it "removes only specified separator" do
      a = []
      "hello world".send(@method, ' ', chomp: true) { |s| a << s }
      a.should == ["hello", "world"]
    end

    # https://bugs.ruby-lang.org/issues/14257
    it "ignores new line characters when separator is specified" do
      a = []
      "hello\n world\n".send(@method, ' ', chomp: true) { |s| a << s }
      a.should == ["hello\n", "world\n"]

      a = []
      "hello\r\n world\r\n".send(@method, ' ', chomp: true) { |s| a << s }
      a.should == ["hello\r\n", "world\r\n"]
    end
  end
end
