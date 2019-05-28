describe :proc_call_block_args, shared: true do
  it "can receive block arguments" do
    Proc.new {|&b| b.send(@method)}.send(@method) {1 + 1}.should == 2
    lambda {|&b| b.send(@method)}.send(@method) {1 + 1}.should == 2
    proc {|&b| b.send(@method)}.send(@method) {1 + 1}.should == 2
  end

  it "yields to the block given at declaration and not to the block argument" do
    proc_creator = Object.new
    def proc_creator.create
      Proc.new do |&b|
        yield
      end
    end
    a_proc = proc_creator.create { 7 }
    a_proc.send(@method) { 3 }.should == 7
  end

  it "can call its block argument declared with a block argument" do
    proc_creator = Object.new
    def proc_creator.create(method_name)
      Proc.new do |&b|
        yield + b.send(method_name)
      end
    end
    a_proc = proc_creator.create(@method) { 7 }
    a_proc.call { 3 }.should == 10
  end
end
