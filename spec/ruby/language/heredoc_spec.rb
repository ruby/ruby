# -*- encoding: us-ascii -*-

require_relative '../spec_helper'

describe "Heredoc string" do

  before :each do
    @ip = 'xxx' # used for interpolation
  end

  it "allows HEREDOC with <<identifier, interpolated" do
    s = <<HERE
foo bar#{@ip}
HERE
    s.should == "foo barxxx\n"
    s.encoding.should == Encoding::US_ASCII
  end

  it 'allow HEREDOC with <<"identifier", interpolated' do
    s = <<"HERE"
foo bar#{@ip}
HERE
    s.should == "foo barxxx\n"
    s.encoding.should == Encoding::US_ASCII
  end

  it "allows HEREDOC with <<'identifier', no interpolation" do
    s = <<'HERE'
foo bar#{@ip}
HERE
    s.should == 'foo bar#{@ip}' + "\n"
    s.encoding.should == Encoding::US_ASCII
  end

  it "allows HEREDOC with <<-identifier, allowing to indent identifier, interpolated" do
    s = <<-HERE
    foo bar#{@ip}
    HERE

    s.should == "    foo barxxx\n"
    s.encoding.should == Encoding::US_ASCII
  end

  it 'allows HEREDOC with <<-"identifier", allowing to indent identifier, interpolated' do
    s = <<-"HERE"
    foo bar#{@ip}
    HERE

    s.should == "    foo barxxx\n"
    s.encoding.should == Encoding::US_ASCII
  end

  it "allows HEREDOC with <<-'identifier', allowing to indent identifier, no interpolation" do
    s = <<-'HERE'
    foo bar#{@ip}
    HERE

    s.should == '    foo bar#{@ip}' + "\n"
    s.encoding.should == Encoding::US_ASCII
  end

  it 'raises SyntaxError if quoted HEREDOC identifier is ending not on same line' do
    -> {
      eval %{<<"HERE\n"\nraises syntax error\nHERE}
    }.should raise_error(SyntaxError)
  end

  it "allows HEREDOC with <<~'identifier', allowing to indent identifier and content" do
    require_relative 'fixtures/squiggly_heredoc'
    SquigglyHeredocSpecs.message.should == "character density, n.:\n  The number of very weird people in the office.\n"
  end

  it "trims trailing newline character for blank HEREDOC with <<~'identifier'" do
    require_relative 'fixtures/squiggly_heredoc'
    SquigglyHeredocSpecs.blank.should == ""
  end

  it 'allows HEREDOC with <<~identifier, interpolated' do
    require_relative 'fixtures/squiggly_heredoc'
    SquigglyHeredocSpecs.unquoted.should == "unquoted interpolated\n"
  end

  it 'allows HEREDOC with <<~"identifier", interpolated' do
    require_relative 'fixtures/squiggly_heredoc'
    SquigglyHeredocSpecs.doublequoted.should == "doublequoted interpolated\n"
  end

  it "allows HEREDOC with <<~'identifier', no interpolation" do
    require_relative 'fixtures/squiggly_heredoc'
    SquigglyHeredocSpecs.singlequoted.should == "singlequoted \#{\"interpolated\"}\n"
  end

  it "allows HEREDOC with <<~'identifier', no interpolation, with backslash" do
    require_relative 'fixtures/squiggly_heredoc'
    SquigglyHeredocSpecs.backslash.should == "a\nbc\n"
  end

  it "selects the least-indented line and removes its indentation from all the lines" do
    require_relative 'fixtures/squiggly_heredoc'
    SquigglyHeredocSpecs.least_indented_on_the_first_line.should == "a\n  b\n    c\n"
    SquigglyHeredocSpecs.least_indented_on_the_last_line.should == "    a\n  b\nc\n"
  end

  it "selects the least-indented line and removes its indentation from all the lines for <<~'identifier'" do
    require_relative 'fixtures/squiggly_heredoc'
    SquigglyHeredocSpecs.least_indented_on_the_first_line_single.should == "a\n  b\n    c\n"
    SquigglyHeredocSpecs.least_indented_on_the_last_line_single.should == "    a\n  b\nc\n"
  end

  it "reports line numbers inside HEREDOC with method call" do
    -> {
      <<-HERE.chomp
        a
        b
        #{c}
      HERE
    }.should raise_error(NameError) { |e| e.backtrace[0].should.start_with?("#{__FILE__}:#{__LINE__ - 2}") }
  end
end
