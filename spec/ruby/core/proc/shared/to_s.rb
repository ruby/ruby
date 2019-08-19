describe :proc_to_s, shared: true do
  describe "for a proc created with Proc.new" do
    it "returns a description optionally including file and line number" do
      Proc.new { "hello" }.send(@method).should =~ /^#<Proc:([^ ]*?)( ([^ ]*)\/to_s\.rb:4)?>$/
    end

    it "has a binary encoding" do
      Proc.new { "hello" }.send(@method).encoding.should == Encoding::BINARY
    end
  end

  describe "for a proc created with lambda" do
    it "returns a description including '(lambda)' and optionally including file and line number" do
      -> { "hello" }.send(@method).should =~ /^#<Proc:([^ ]*?)( ([^ ]*)\/to_s\.rb:14)? \(lambda\)>$/
    end

    it "has a binary encoding" do
      -> { "hello" }.send(@method).encoding.should == Encoding::BINARY
    end
  end

  describe "for a proc created with proc" do
    it "returns a description optionally including file and line number" do
      proc { "hello" }.send(@method).should =~ /^#<Proc:([^ ]*?)( ([^ ]*)\/to_s\.rb:24)?>$/
    end

    it "has a binary encoding" do
      proc { "hello" }.send(@method).encoding.should == Encoding::BINARY
    end
  end

  describe "for a proc created with UnboundMethod#to_proc" do
    it "returns a description including '(lambda)' and optionally including file and line number" do
      def hello; end
      method("hello").to_proc.send(@method).should =~ /^#<Proc:([^ ]*?)( ([^ ]*)\/to_s\.rb:22)? \(lambda\)>$/
    end

    it "has a binary encoding" do
      def hello; end
      method("hello").to_proc.send(@method).encoding.should == Encoding::BINARY
    end
  end

  describe "for a proc created with Symbol#to_proc" do
    it "returns a description including '(&:symbol)'" do
      proc = :foobar.to_proc
      proc.send(@method).should =~ /^#<Proc:0x\h+\(&:foobar\)>$/
    end

    it "has a binary encoding" do
      proc = :foobar.to_proc
      proc.send(@method).encoding.should == Encoding::BINARY
    end
  end
end
