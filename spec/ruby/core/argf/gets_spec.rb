require_relative '../../spec_helper'
require_relative 'shared/gets'

describe "ARGF.gets" do
  it_behaves_like :argf_gets, :gets
end

describe "ARGF.gets" do
  it_behaves_like :argf_gets_inplace_edit, :gets
end

describe "ARGF.gets" do
  before :each do
    @file1_name = fixture __FILE__, "file1.txt"
    @file2_name = fixture __FILE__, "file2.txt"

    @file1 = File.readlines @file1_name
    @file2 = File.readlines @file2_name
  end

  it "returns nil when reaching end of files" do
    argf [@file1_name, @file2_name] do
      total = @file1.size + @file2.size
      total.times { @argf.gets }
      @argf.gets.should == nil
    end
  end

  before :each do
    @external = Encoding.default_external
    @internal = Encoding.default_internal

    Encoding.default_external = Encoding::UTF_8
    Encoding.default_internal = nil
  end

  after :each do
    Encoding.default_external = @external
    Encoding.default_internal = @internal
  end

  it "reads the contents of the file with default encoding" do
    Encoding.default_external = Encoding::US_ASCII
    argf [@file1_name, @file2_name] do
      @argf.gets.encoding.should == Encoding::US_ASCII
    end
  end

end

describe "ARGF.gets when reading $stdin and $stdin is not an IO" do
  before :each do
    @stdin = $stdin
    $stdin = StringIO.new("a\nb\n")
    @argf_stdin = ARGF.class.new
  end

  after :each do
    $stdin = @stdin
  end

  it "increments lineno for each line read" do
    @argf_stdin.gets
    @argf_stdin.gets
    @argf_stdin.lineno.should == 2
  end

  it "raises NoMethodError when $stdin has no public gets" do
    $stdin = Object.new
    -> { ARGF.class.new.gets }.should.raise(NoMethodError)
  end
end
