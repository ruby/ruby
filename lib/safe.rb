# this is a safe-mode for ruby, which is still incomplete.

unless defined? SecurityError
  class SecurityError<Exception
  end
end

module Restricted

  printf STDERR, "feel free for some warnings:\n" if $VERBOSE
  module Bastion
    include Restricted
    extend Restricted
    BINDING = binding
    def Bastion.to_s; "main" end
  end

  class R_File<File
    NG_FILE_OP = []
    def R_File.open(*args)
      raise SecurityError, "can't use File.open() in safe mode" #'
    end
  end

  IO = nil
  File = R_File
  FileTest = nil
  Dir = nil
  ObjectSpace = nil

  def eval(string)
    begin
      super(string, Bastion::BINDING)
    rescue
      $@ = caller
      raise
    end
  end
  module_function :eval

  DEFAULT_SECURITY_MANAGER = Object.new

  def Restricted.set_securuty_manager(sec_man)
    if @sec_man
      raise SecurityError, "cannot change security manager"
    end
    @sec_man = sec_man
  end

  def Restricted.securuty_manager
    return @sec_man if @sec_man
    return DEFAULT_SECURITY_MANAGER
  end

  for cmd in ["test", "require", "load", "open", "system"]
    eval format("def DEFAULT_SECURITY_MANAGER.%s(*args)
                   raise SecurityError, \"can't use %s() in safe mode\"
                 end", cmd, cmd) #'
    eval format("def %s(*args)
                   Restricted.securuty_manager.%s(*args)
                 end", cmd, cmd) 
  end

  def `(arg) #`
    Restricted.securuty_manager.send(:`, arg) #`)
  end

  def DEFAULT_SECURITY_MANAGER.`(arg) #`
    raise SecurityError, "can't use backquote(``) in safe mode"
  end
end

if $DEBUG
  p eval("File.open('/dev/null')")
  p Restricted.eval("self")
  p Restricted.eval("open('/dev/null')")
  p Restricted.eval("File.open('/dev/null')")
end
