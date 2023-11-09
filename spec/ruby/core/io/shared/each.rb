# -*- encoding: utf-8 -*-
require_relative '../fixtures/classes'

describe :io_each, shared: true do
  before :each do
    @io = IOSpecs.io_fixture "lines.txt"
    ScratchPad.record []
  end

  after :each do
    @io.close if @io
  end

  describe "with no separator" do
    it "yields each line to the passed block" do
      @io.send(@method) { |s| ScratchPad << s }
      ScratchPad.recorded.should == IOSpecs.lines
    end

    it "yields each line starting from the current position" do
      @io.pos = 41
      @io.send(@method) { |s| ScratchPad << s }
      ScratchPad.recorded.should == IOSpecs.lines[2..-1]
    end

    it "returns self" do
      @io.send(@method) { |l| l }.should equal(@io)
    end

    it "does not change $_" do
      $_ = "test"
      @io.send(@method) { |s| s }
      $_.should == "test"
    end

    it "raises an IOError when self is not readable" do
      -> { IOSpecs.closed_io.send(@method) {} }.should raise_error(IOError)
    end

    it "makes line count accessible via lineno" do
      @io.send(@method) { ScratchPad << @io.lineno }
      ScratchPad.recorded.should == [ 1,2,3,4,5,6,7,8,9 ]
    end

    it "makes line count accessible via $." do
      @io.send(@method) { ScratchPad << $. }
      ScratchPad.recorded.should == [ 1,2,3,4,5,6,7,8,9 ]
    end

    describe "when no block is given" do
      it "returns an Enumerator" do
        enum = @io.send(@method)
        enum.should be_an_instance_of(Enumerator)

        enum.each { |l| ScratchPad << l }
        ScratchPad.recorded.should == IOSpecs.lines
      end

      describe "returned Enumerator" do
        describe "size" do
          it "should return nil" do
            @io.send(@method).size.should == nil
          end
        end
      end
    end
  end

  describe "with limit" do
    describe "when limit is 0" do
      it "raises an ArgumentError" do
        # must pass block so Enumerator is evaluated and raises
        -> { @io.send(@method, 0){} }.should raise_error(ArgumentError)
      end
    end

    it "does not accept Integers that don't fit in a C off_t" do
      -> { @io.send(@method, 2**128){} }.should raise_error(RangeError)
    end
  end

  describe "when passed a String containing one space as a separator" do
    it "uses the passed argument as the line separator" do
      @io.send(@method, " ") { |s| ScratchPad << s }
      ScratchPad.recorded.should == IOSpecs.lines_space_separator
    end

    it "does not change $_" do
      $_ = "test"
      @io.send(@method, " ") { |s| }
      $_.should == "test"
    end

    it "tries to convert the passed separator to a String using #to_str" do
      obj = mock("to_str")
      obj.stub!(:to_str).and_return(" ")

      @io.send(@method, obj) { |l| ScratchPad << l }
      ScratchPad.recorded.should == IOSpecs.lines_space_separator
    end
  end

  describe "when passed nil as a separator" do
    it "yields self's content starting from the current position when the passed separator is nil" do
      @io.pos = 100
      @io.send(@method, nil) { |s| ScratchPad << s }
      ScratchPad.recorded.should == ["qui a linha cinco.\nHere is line six.\n"]
    end
  end

  describe "when passed an empty String as a separator" do
    it "yields each paragraph" do
      @io.send(@method, "") { |s| ScratchPad << s }
      ScratchPad.recorded.should == IOSpecs.paragraphs
    end

    it "discards leading newlines" do
      @io.readline
      @io.readline
      @io.send(@method, "") { |s| ScratchPad << s }
      ScratchPad.recorded.should == IOSpecs.paragraphs[1..-1]
    end
  end

  describe "with both separator and limit" do
    describe "when no block is given" do
      it "returns an Enumerator" do
        enum = @io.send(@method, nil, 1024)
        enum.should be_an_instance_of(Enumerator)

        enum.each { |l| ScratchPad << l }
        ScratchPad.recorded.should == [IOSpecs.lines.join]
      end

      describe "returned Enumerator" do
        describe "size" do
          it "should return nil" do
            @io.send(@method, nil, 1024).size.should == nil
          end
        end
      end
    end

    describe "when a block is given" do
      it "accepts an empty block" do
        @io.send(@method, nil, 1024) {}.should equal(@io)
      end

      describe "when passed nil as a separator" do
        it "yields self's content starting from the current position when the passed separator is nil" do
          @io.pos = 100
          @io.send(@method, nil, 1024) { |s| ScratchPad << s }
          ScratchPad.recorded.should == ["qui a linha cinco.\nHere is line six.\n"]
        end
      end

      describe "when passed an empty String as a separator" do
        it "yields each paragraph" do
          @io.send(@method, "", 1024) { |s| ScratchPad << s }
          ScratchPad.recorded.should == IOSpecs.paragraphs
        end

        it "discards leading newlines" do
          @io.readline
          @io.readline
          @io.send(@method, "", 1024) { |s| ScratchPad << s }
          ScratchPad.recorded.should == IOSpecs.paragraphs[1..-1]
        end
      end
    end
  end

  describe "when passed chomp" do
    it "yields each line without trailing newline characters to the passed block" do
      @io.send(@method, chomp: true) { |s| ScratchPad << s }
      ScratchPad.recorded.should == IOSpecs.lines_without_newline_characters
    end

    it "raises exception when options passed as Hash" do
      -> {
        @io.send(@method, { chomp: true }) { |s| }
      }.should raise_error(TypeError)

      -> {
        @io.send(@method, "\n", 1, { chomp: true }) { |s| }
      }.should raise_error(ArgumentError, "wrong number of arguments (given 3, expected 0..2)")
    end
  end

  describe "when passed chomp and a separator" do
    it "yields each line without separator to the passed block" do
      @io.send(@method, " ", chomp: true) { |s| ScratchPad << s }
      ScratchPad.recorded.should == IOSpecs.lines_space_separator_without_trailing_spaces
    end
  end

  describe "when passed chomp and empty line as a separator" do
    it "yields each paragraph without trailing new line characters" do
      @io.send(@method, "", 1024, chomp: true) { |s| ScratchPad << s }
      ScratchPad.recorded.should == IOSpecs.paragraphs_without_trailing_new_line_characters
    end
  end

  describe "when passed chomp and nil as a separator" do
    ruby_version_is "3.2" do
      it "yields self's content" do
        @io.pos = 100
        @io.send(@method, nil, chomp: true) { |s| ScratchPad << s }
        ScratchPad.recorded.should == ["qui a linha cinco.\nHere is line six.\n"]
      end
    end

    ruby_version_is ""..."3.2" do
      it "yields self's content without trailing new line character" do
        @io.pos = 100
        @io.send(@method, nil, chomp: true) { |s| ScratchPad << s }
        ScratchPad.recorded.should == ["qui a linha cinco.\nHere is line six."]
      end
    end
  end

  describe "when passed chomp, nil as a separator, and a limit" do
    it "yields each line of limit size without truncating trailing new line character" do
      # 43 - is a size of the 1st paragraph in the file
      @io.send(@method, nil, 43, chomp: true) { |s| ScratchPad << s }

      ScratchPad.recorded.should == [
        "Voici la ligne une.\nQui è la linea due.\n\n\n",
        "Aquí está la línea tres.\n" + "Hier ist Zeile ",
        "vier.\n\nEstá aqui a linha cinco.\nHere is li",
        "ne six.\n"
      ]
    end
  end

  describe "when passed too many arguments" do
    it "raises ArgumentError" do
      -> {
        @io.send(@method, "", 1, "excess argument", chomp: true) {}
      }.should raise_error(ArgumentError)
    end
  end
end

describe :io_each_default_separator, shared: true do
  before :each do
    @io = IOSpecs.io_fixture "lines.txt"
    ScratchPad.record []
    suppress_warning {@sep, $/ = $/, " "}
  end

  after :each do
    @io.close if @io
    suppress_warning {$/ = @sep}
  end

  it "uses $/ as the default line separator" do
    @io.send(@method) { |s| ScratchPad << s }
    ScratchPad.recorded.should == IOSpecs.lines_space_separator
  end
end
