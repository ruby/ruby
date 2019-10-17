describe :command_line_change_directory, shared: true do
  before :all do
    @script  = fixture(__FILE__, 'change_directory_script.rb')
    @tempdir = File.dirname(@script)
  end

  it 'changes the PWD when using a file' do
    output = ruby_exe(@script, options: "#{@method} #{@tempdir}")
    output.should == @tempdir
  end

  it 'does not need a space after -C for the argument' do
    output = ruby_exe(@script, options: "#{@method}#{@tempdir}")
    output.should == @tempdir
  end

  it 'changes the PWD when using -e' do
    output = ruby_exe(nil, options: "#{@method} #{@tempdir} -e 'print Dir.pwd'")
    output.should == @tempdir
  end
end
