describe :io_readlines, shared: true do
  it "raises TypeError if the first parameter is nil" do
    -> { IO.send(@method, nil, &@object) }.should raise_error(TypeError)
  end

  it "raises an Errno::ENOENT if the file does not exist" do
    name = tmp("nonexistent.txt")
    -> { IO.send(@method, name, &@object) }.should raise_error(Errno::ENOENT)
  end

  it "yields a single string with entire content when the separator is nil" do
    result = IO.send(@method, @name, nil, &@object)
    (result ? result : ScratchPad.recorded).should == [IO.read(@name)]
  end

  it "yields a sequence of paragraphs when the separator is an empty string" do
    result = IO.send(@method, @name, "", &@object)
    (result ? result : ScratchPad.recorded).should == IOSpecs.lines_empty_separator
  end

  it "yields a sequence of lines without trailing newline characters when chomp is passed" do
    result = IO.send(@method, @name, chomp: true, &@object)
    (result ? result : ScratchPad.recorded).should == IOSpecs.lines_without_newline_characters
  end
end

describe :io_readlines_options_19, shared: true do
  before :each do
    @filename = tmp("io readlines options")
  end

  after :each do
    rm_r @filename
  end

  describe "when passed name" do
    it "calls #to_path to convert the name" do
      name = mock("io name to_path")
      name.should_receive(:to_path).and_return(@name)
      IO.send(@method, name, &@object)
    end

    it "defaults to $/ as the separator" do
      result = IO.send(@method, @name, &@object)
      (result ? result : ScratchPad.recorded).should == IOSpecs.lines
    end
  end

  describe "when passed name, object" do
    it "calls #to_str to convert the object to a separator" do
      sep = mock("io readlines separator")
      sep.should_receive(:to_str).at_least(1).and_return(" ")
      result = IO.send(@method, @name, sep, &@object)
      (result ? result : ScratchPad.recorded).should == IOSpecs.lines_space_separator
    end

    describe "when the object is an Integer" do
      before :each do
        @sep = $/
      end

      after :each do
        suppress_warning {$/ = @sep}
      end

      it "defaults to $/ as the separator" do
        suppress_warning {$/ = " "}
        result = IO.send(@method, @name, 10, &@object)
        (result ? result : ScratchPad.recorded).should == IOSpecs.lines_space_separator_limit
      end

      it "uses the object as a limit if it is an Integer" do
        result = IO.send(@method, @name, 10, &@object)
        (result ? result : ScratchPad.recorded).should == IOSpecs.lines_limit
      end

      it "ignores the object as a limit if it is negative" do
        result = IO.send(@method, @name, -2, &@object)
        (result ? result : ScratchPad.recorded).should == IOSpecs.lines
      end

      it "does not accept Integers that don't fit in a C off_t" do
        -> { IO.send(@method, @name, 2**128, &@object) }.should raise_error(RangeError)
      end

      ruby_bug "#18767", ""..."3.3" do
        describe "when passed limit" do
          it "raises ArgumentError when passed 0 as a limit" do
            -> { IO.send(@method, @name, 0, &@object) }.should raise_error(ArgumentError)
          end
        end
      end
    end

    describe "when the object is a String" do
      it "uses the value as the separator" do
        result = IO.send(@method, @name, " ", &@object)
        (result ? result : ScratchPad.recorded).should == IOSpecs.lines_space_separator
      end

      it "accepts non-ASCII data as separator" do
        result = IO.send(@method, @name, "\303\250".force_encoding("utf-8"), &@object)
        (result ? result : ScratchPad.recorded).should == IOSpecs.lines_arbitrary_separator
      end
    end

    describe "when the object is an options Hash" do
      it "raises TypeError exception" do
        -> {
          IO.send(@method, @name, { chomp: true }, &@object)
        }.should raise_error(TypeError)
      end
    end

    describe "when the object is neither Integer nor String" do
      it "raises TypeError exception" do
        obj = mock("not io readlines limit")

        -> {
          IO.send(@method, @name, obj, &@object)
        }.should raise_error(TypeError)
      end
    end
  end

  describe "when passed name, keyword arguments" do
    it "uses the keyword arguments as options" do
      result = IO.send(@method, @name, mode: "r", &@object)
      (result ? result : ScratchPad.recorded).should == IOSpecs.lines
    end
  end

  describe "when passed name, object, object" do
    describe "when the first object is a String" do
      it "uses the second object as a limit if it is an Integer" do
        result = IO.send(@method, @name, " ", 10, &@object)
        (result ? result : ScratchPad.recorded).should == IOSpecs.lines_space_separator_limit
      end

      it "calls #to_int to convert the second object" do
        limit = mock("io readlines limit")
        limit.should_receive(:to_int).at_least(1).and_return(10)
        result = IO.send(@method, @name, " ", limit, &@object)
        (result ? result : ScratchPad.recorded).should == IOSpecs.lines_space_separator_limit
      end
    end

    describe "when the first object is not a String or Integer" do
      it "calls #to_str to convert the object to a String" do
        sep = mock("io readlines separator")
        sep.should_receive(:to_str).at_least(1).and_return(" ")
        result = IO.send(@method, @name, sep, 10, &@object)
        (result ? result : ScratchPad.recorded).should == IOSpecs.lines_space_separator_limit
      end

      it "uses the second object as a limit if it is an Integer" do
        result = IO.send(@method, @name, " ", 10, &@object)
        (result ? result : ScratchPad.recorded).should == IOSpecs.lines_space_separator_limit
      end

      it "calls #to_int to convert the second object" do
        limit = mock("io readlines limit")
        limit.should_receive(:to_int).at_least(1).and_return(10)
        result = IO.send(@method, @name, " ", limit, &@object)
        (result ? result : ScratchPad.recorded).should == IOSpecs.lines_space_separator_limit
      end
    end

    describe "when the second object is neither Integer nor String" do
      it "raises TypeError exception" do
        obj = mock("not io readlines limit")

        -> {
          IO.send(@method, @name, " ", obj, &@object)
        }.should raise_error(TypeError)
      end
    end

    describe "when the second object is an options Hash" do
      it "raises TypeError exception" do
        -> {
          IO.send(@method, @name, "", { chomp: true }, &@object)
        }.should raise_error(TypeError)
      end
    end
  end

  describe "when passed name, object, keyword arguments" do
    describe "when the first object is an Integer" do
      it "uses the keyword arguments as options" do
        -> do
          IO.send(@method, @filename, 10, mode: "w", &@object)
        end.should raise_error(IOError)
      end
    end

    describe "when the first object is a String" do
      it "uses the keyword arguments as options" do
        -> do
          IO.send(@method, @filename, " ", mode: "w", &@object)
        end.should raise_error(IOError)
      end
    end

    describe "when the first object is not a String or Integer" do
      it "uses the keyword arguments as options" do
        sep = mock("io readlines separator")
        sep.should_receive(:to_str).at_least(1).and_return(" ")

        -> do
          IO.send(@method, @filename, sep, mode: "w", &@object)
        end.should raise_error(IOError)
      end
    end
  end

  describe "when passed name, separator, limit, keyword arguments" do
    it "calls #to_path to convert the name object" do
      name = mock("io name to_path")
      name.should_receive(:to_path).and_return(@name)
      result = IO.send(@method, name, " ", 10, mode: "r", &@object)
      (result ? result : ScratchPad.recorded).should == IOSpecs.lines_space_separator_limit
    end

    it "calls #to_str to convert the separator object" do
      sep = mock("io readlines separator")
      sep.should_receive(:to_str).at_least(1).and_return(" ")
      result = IO.send(@method, @name, sep, 10, mode: "r", &@object)
      (result ? result : ScratchPad.recorded).should == IOSpecs.lines_space_separator_limit
    end

    it "calls #to_int to convert the limit argument" do
      limit = mock("io readlines limit")
      limit.should_receive(:to_int).at_least(1).and_return(10)
      result = IO.send(@method, @name, " ", limit, mode: "r", &@object)
      (result ? result : ScratchPad.recorded).should == IOSpecs.lines_space_separator_limit
    end

    it "uses the keyword arguments as options" do
      -> do
        IO.send(@method, @filename, " ", 10, mode: "w", &@object)
      end.should raise_error(IOError)
    end

    describe "when passed chomp, nil as a separator, and a limit" do
      it "yields each line of limit size without truncating trailing new line character" do
        # 43 - is a size of the 1st paragraph in the file
        result = IO.send(@method, @name, nil, 43, chomp: true, &@object)

        (result ? result : ScratchPad.recorded).should == [
          "Voici la ligne une.\nQui è la linea due.\n\n\n",
          "Aquí está la línea tres.\n" + "Hier ist Zeile ",
          "vier.\n\nEstá aqui a linha cinco.\nHere is li",
          "ne six.\n"
        ]
      end
    end
  end
end
