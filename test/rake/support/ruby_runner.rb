module RubyRunner
  include FileUtils

  # Run a shell Ruby command with command line options (using the
  # default test options). Output is captured in @out and @err
  def ruby(*option_list)
    run_ruby(@ruby_options + option_list)
  end

  # Run a command line rake with the give rake options.  Default
  # command line ruby options are included.  Output is captured in
  # @out and @err
  def rake(*rake_options)
    run_ruby @ruby_options + [@rake_exec] + rake_options
  end

  # Low level ruby command runner ...
  def run_ruby(option_list)
    puts "COMMAND: [#{RUBY} #{option_list.join ' '}]" if @verbose

    inn, out, err, wait = Open3.popen3(RUBY, *option_list)
    inn.close

    @exit = wait ? wait.value : $?
    @out = out.read
    @err = err.read

    puts "OUTPUT:  [#{@out}]" if @verbose
    puts "ERROR:   [#{@err}]" if @verbose
    puts "EXIT:    [#{@exit.inspect}]" if @verbose
    puts "PWD:     [#{Dir.pwd}]" if @verbose
  end
end
