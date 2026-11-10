require 'stringio'

describe :argf_gets, shared: true do
  before :each do
    @file1_name = fixture __FILE__, "file1.txt"
    @file2_name = fixture __FILE__, "file2.txt"
    @stdin_name = fixture __FILE__, "stdin.txt"

    @file1 = File.readlines @file1_name
    @file2 = File.readlines @file2_name
    @stdin = File.read @stdin_name
  end

  it "reads one line of a file" do
    argf [@file1_name] do
      @argf.send(@method).should == @file1.first
    end
  end

  it "reads one line of a file without the trailing separator when passed chomp" do
    argf [@file1_name] do
      @argf.send(@method, chomp: true).should == @file1.first.chomp
    end
  end

  it "reads up to the limit when passed a separator and a limit" do
    argf [@file1_name] do
      @argf.send(@method, ".", 4).should == "file"
    end
  end

  it "reads one separated section without the separator when passed a separator and chomp" do
    argf [@file1_name] do
      @argf.send(@method, ".", chomp: true).should == "file1"
    end
  end

  describe "when reading $stdin and $stdin is not an IO" do
    before :each do
      @stdin = $stdin
      $stdin = StringIO.new("a\nb\n")
      @stdin_argf = ARGF.class.new
    end

    after :each do
      $stdin = @stdin
    end

    it "reads each line of $stdin" do
      @stdin_argf.send(@method).should == "a\n"
      @stdin_argf.send(@method).should == "b\n"
    end

    it "passes keywords on to $stdin" do
      @stdin_argf.send(@method, chomp: true).should == "a"
    end
  end

  it "reads all lines of a file" do
    argf [@file1_name] do
      lines = []
      @file1.size.times { lines << @argf.send(@method) }
      lines.should == @file1
    end
  end

  it "reads all lines of stdin" do
    total = @stdin.count $/
    stdin = ruby_exe(
      "#{total}.times { print ARGF.send(#{@method.inspect}) }",
      args: "< #{@stdin_name}")
    stdin.should == @stdin
  end

  it "reads all lines of two files" do
    argf [@file1_name, @file2_name] do
      total = @file1.size + @file2.size
      lines = []
      total.times { lines << @argf.send(@method) }
      lines.should == @file1 + @file2
    end
  end

  it "sets $_ global variable with each line read" do
    argf [@file1_name, @file2_name] do
      total = @file1.size + @file2.size
      total.times do
        line = @argf.send(@method)
        $_.should == line
      end
    end
  end
end

describe :argf_gets_inplace_edit, shared: true do
  before :each do
    @file1_name = fixture __FILE__, "file1.txt"
    @file2_name = fixture __FILE__, "file2.txt"

    @tmp1_name  = tmp "file1.txt"
    @tmp2_name  = tmp "file2.txt"

    @tmp1_name_bak = @tmp1_name + ".bak"
    @tmp2_name_bak = @tmp2_name + ".bak"

    cp @file1_name, @tmp1_name
    cp @file2_name, @tmp2_name

    method = "ARGF.send(#{@method.inspect})"
    @code = "begin while line = #{method} do puts 'x' end rescue EOFError; end"
  end

  after :each do
    rm_r @tmp1_name, @tmp2_name, @tmp1_name_bak, @tmp2_name_bak
  end

  # -i with no backup extension is not supported on Windows
  platform_is_not :windows do
    it "modifies the files when in place edit mode is on" do
      ruby_exe(@code,
               options: "-i",
               args: "#{@tmp1_name} #{@tmp2_name}")

      File.read(@tmp1_name).should == "x\nx\n"
      File.read(@tmp2_name).should == "x\nx\n"
    end
  end

  it "modifies and backups two files when in place edit mode is on" do
    ruby_exe(@code,
             options: "-i.bak",
             args: "#{@tmp1_name} #{@tmp2_name}")

    File.read(@tmp1_name).should == "x\nx\n"
    File.read(@tmp2_name).should == "x\nx\n"

    File.read(@tmp1_name_bak).should == "file1.1\nfile1.2\n"
    File.read(@tmp2_name_bak).should == "line2.1\nline2.2\n"
  end
end
