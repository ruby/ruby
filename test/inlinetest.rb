module InlineTest
  def loadtest(libname)
    in_critical do
      in_progname(libpath(libname)) do
	Kernel.load(libname)
      end
    end
  end
  module_function :loadtest

  def loadtest__END__part(libname)
    program = File.open(libpath(libname)) { |f| f.read }
    mainpart, endpart = program.split(/^__END__$/)
    if endpart.nil?
      raise RuntimeError.new("No __END__ part in the library '#{filename}'")
    end
    require(libname)
    eval(endpart)
  end
  module_function :loadtest__END__part

  def self.in_critical
    th_criticality = Thread.critical
    Thread.critical = true
    begin
      yield
    ensure
      Thread.critical = th_criticality
    end
  end

  def self.in_progname(progname)
    progname_backup = $0.dup
    $0.replace(progname)
    begin
      yield
    ensure
      $0.replace(progname_backup)
    end
  end

  def self.libpath(libname)
    libpath = nil
    $:.find do |path|
      File.file?(testname = File.join(path, libname)) && libpath = testname
    end
    if libpath.nil?
      raise RuntimeError.new("'#{libname}' not found")
    end
    libpath
  end
end
