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
  end

  it 'allow HEREDOC with <<"identifier", interpolated' do
    s = <<"HERE"
foo bar#{@ip}
HERE
    s.should == "foo barxxx\n"
  end

  it "allows HEREDOC with <<'identifier', no interpolation" do
    s = <<'HERE'
foo bar#{@ip}
HERE
    s.should == 'foo bar#{@ip}' + "\n"
  end

  it "allows HEREDOC with <<-identifier, allowing to indent identifier, interpolated" do
    s = <<-HERE
    foo bar#{@ip}
    HERE

    s.should == "    foo barxxx\n"
  end

  it 'allows HEREDOC with <<-"identifier", allowing to indent identifier, interpolated' do
    s = <<-"HERE"
    foo bar#{@ip}
    HERE

    s.should == "    foo barxxx\n"
  end

  it "allows HEREDOC with <<-'identifier', allowing to indent identifier, no interpolation" do
    s = <<-'HERE'
    foo bar#{@ip}
    HERE

    s.should == '    foo bar#{@ip}' + "\n"
  end

  ruby_version_is "2.3" do
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

    it "selects the least-indented line and removes its indentation from all the lines" do
      require_relative 'fixtures/squiggly_heredoc'
      SquigglyHeredocSpecs.least_indented_on_the_last_line.should == "    a\n  b\nc\n"
    end
  end
end
