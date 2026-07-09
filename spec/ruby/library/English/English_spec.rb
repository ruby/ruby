require_relative '../../spec_helper'

require 'English'

describe "English" do
  it "aliases $ERROR_INFO to $!" do
    begin
      raise "error"
    rescue
      $ERROR_INFO.should_not == nil
      $ERROR_INFO.should == $!
    end
    $ERROR_INFO.should == nil
  end

  it "aliases $ERROR_POSITION to $@" do
    begin
      raise "error"
    rescue
      $ERROR_POSITION.should_not == nil
      $ERROR_POSITION.should == $@
    end
    $ERROR_POSITION.should == nil
  end

  it "aliases $FS to $;" do
    original = $;
    suppress_warning {$; = ","}
    $FS.should_not == nil
    $FS.should == $;
    suppress_warning {$; = original}
  end

  it "aliases $FIELD_SEPARATOR to $;" do
    original = $;
    suppress_warning {$; = ","}
    $FIELD_SEPARATOR.should_not == nil
    $FIELD_SEPARATOR.should == $;
    suppress_warning {$; = original}
  end

  it "aliases $OFS to $," do
    original = $,
    suppress_warning {$, = "|"}
    $OFS.should_not == nil
    $OFS.should == $,
    suppress_warning {$, = original}
  end

  it "aliases $OUTPUT_FIELD_SEPARATOR to $," do
    original = $,
    suppress_warning {$, = "|"}
    $OUTPUT_FIELD_SEPARATOR.should_not == nil
    $OUTPUT_FIELD_SEPARATOR.should == $,
    suppress_warning {$, = original}
  end

  it "aliases $RS to $/" do
    $RS.should_not == nil
    $RS.should == $/
  end

  it "aliases $INPUT_RECORD_SEPARATOR to $/" do
    $INPUT_RECORD_SEPARATOR.should_not == nil
    $INPUT_RECORD_SEPARATOR.should == $/
  end

  it "aliases $ORS to $\\" do
    original = $\
    suppress_warning {$\ = "\t"}
    $ORS.should_not == nil
    $ORS.should == $\
    suppress_warning {$\ = original}
  end

  it "aliases $OUTPUT_RECORD_SEPARATOR to $\\" do
    original = $\
    suppress_warning {$\ = "\t"}
    $OUTPUT_RECORD_SEPARATOR.should_not == nil
    $OUTPUT_RECORD_SEPARATOR.should == $\
    suppress_warning {$\ = original}
  end

  it "aliases $INPUT_LINE_NUMBER to $." do
    $INPUT_LINE_NUMBER.should_not == nil
    $INPUT_LINE_NUMBER.should == $.
  end

  it "aliases $NR to $." do
    $NR.should_not == nil
    $NR.should == $.
  end

  it "aliases $LAST_READ_LINE to $_ needs to be reviewed for spec completeness"

  it "aliases $DEFAULT_OUTPUT to $>" do
    $DEFAULT_OUTPUT.should_not == nil
    $DEFAULT_OUTPUT.should == $>
  end

  it "aliases $DEFAULT_INPUT to $<" do
    $DEFAULT_INPUT.should_not == nil
    $DEFAULT_INPUT.should == $<
  end

  it "aliases $PID to $$" do
    $PID.should_not == nil
    $PID.should == $$
  end

  it "aliases $PID to $$" do
    $PID.should_not == nil
    $PID.should == $$
  end

  it "aliases $PROCESS_ID to $$" do
    $PROCESS_ID.should_not == nil
    $PROCESS_ID.should == $$
  end

  it "aliases $CHILD_STATUS to $?" do
    ruby_exe('exit 0')
    $CHILD_STATUS.should_not == nil
    $CHILD_STATUS.should == $?
  end

  it "aliases $LAST_MATCH_INFO to $~" do
    /c(a)t/ =~ "cat"
    $LAST_MATCH_INFO.should_not == nil
    $LAST_MATCH_INFO.should == $~
  end

  it "aliases $ARGV to $*" do
    $ARGV.should_not == nil
    $ARGV.should == $*
  end

  it "aliases $MATCH to $&" do
    /c(a)t/ =~ "cat"
    $MATCH.should_not == nil
    $MATCH.should == $&
  end

  it "aliases $PREMATCH to $`" do
    /c(a)t/ =~ "cat"
    $PREMATCH.should_not == nil
    $PREMATCH.should == $`
  end

  it "aliases $POSTMATCH to $'" do
    /c(a)t/ =~ "cat"
    $POSTMATCH.should_not == nil
    $POSTMATCH.should == $'
  end

  it "aliases $LAST_PAREN_MATCH to $+" do
    /c(a)t/ =~ "cat"
    $LAST_PAREN_MATCH.should_not == nil
    $LAST_PAREN_MATCH.should == $+
  end
end
