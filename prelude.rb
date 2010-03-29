# currently empty

module Process
  # call-seq:
  #    Process.daemon()			       => 0
  #    Process.daemon(nochdir=nil,noclose=nil) => 0
  # 
  # Detach the process from controlling terminal and run in
  # the background as system daemon.  Unless the argument
  # nochdir is true (i.e. non false), it changes the current
  # working directory to the root ("/"). Unless the argument
  # noclose is true, daemon() will redirect standard input,
  # standard output and standard error to /dev/null.
  # Return zero on success, or raise one of Errno::*.
  def self.daemon(nochdir = nil, noclose = nil)
    if $SAFE >= 2
      raise SecurityError, "Insecure operation `%s' at level %d", __method__, $SAFE
    end

    fork && exit!(0)

    Process.setsid()

    fork && exit!(0)

    Dir.chdir('/') unless nochdir

    File.open('/dev/null', 'r+') { |f|
      STDIN.reopen(f)
      STDOUT.reopen(f)
      STDERR.reopen(f)
    } unless noclose

    return 0
  end
end
