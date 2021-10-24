require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

RSpec.describe Object, "#argf" do
  before :each do
    @saved_argv = ARGV.dup
    @argv = [__FILE__]
  end

  it "sets @argf to an instance of ARGF.class with the given argv" do
    argf @argv do
      expect(@argf).to be_an_instance_of ARGF.class
      expect(@argf.filename).to eq(@argv.first)
    end
    expect(@argf).to be_nil
  end

  it "does not alter ARGV nor ARGF" do
    argf @argv do
    end
    expect(ARGV).to eq(@saved_argv)
    expect(ARGF.argv).to eq(@saved_argv)
  end

  it "does not close STDIN" do
    argf ['-'] do
    end
    expect(STDIN).not_to be_closed
  end

  it "disallows nested calls" do
    argf @argv do
      expect { argf @argv }.to raise_error
    end
  end
end
