module InlineTest
  def eval_part(libname, sep, part)
    path = libpath(libname)
    program = File.open(path) { |f| f.read }
    mainpart, endpart = program.split(sep)
    if endpart.nil?
      raise RuntimeError.new("No #{part} part in the library '#{filename}'")
    end
    eval(endpart, TOPLEVEL_BINDING, path, mainpart.count("\n")+1)
  end
  module_function :eval_part

  def loadtest(libname)
    require(libname)
    in_critical do
      in_progname(libpath(libname)) do
        eval_part(libname, /^(?=if\s+(?:\$0\s*==\s*__FILE__|__FILE__\s*==\s*\$0)(?:[\#\s]|$))/, '$0 == __FILE__')
      end
    end
  end
  module_function :loadtest

  def loadtest__END__part(libname)
    require(libname)
    eval_part(libname, /^__END__$/, '__END__')
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
