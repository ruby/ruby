#
#   shell/system-command.rb - 
#   	$Release Version: 0.6.0 $
#   	$Revision: 1.2.2.1 $
#   	$Date: 2004/03/21 12:21:11 $
#   	by Keiju ISHITSUKA(Nihon Rational Software Co.,Ltd)
#
# --
#
#   
#

require "shell/filter"

class Shell
  class SystemCommand < Filter
    def initialize(sh, command, *opts)
      if t = opts.find{|opt| !opt.kind_of?(String) && opt.class}
	Shell.Fail Error::TypeError, t.class, "String"
      end
      super(sh)
      @command = command
      @opts = opts
      
      @input_queue = Queue.new
      @pid = nil

      sh.process_controller.add_schedule(self)
    end

    attr_reader :command
    alias name command

    def wait?
      @shell.process_controller.waiting_job?(self)
    end

    def active?
      @shell.process_controller.active_job?(self)
    end

    def input=(inp)
      super
      if active?
	start_export
      end
    end

    def start
      @pid, @pipe_in, @pipe_out = @shell.process_controller.sfork(self) {
	Dir.chdir @shell.pwd
	exec(@command, *@opts)
      }
      if @input
	start_export
      end
      start_import
    end

    def flush
      @pipe_out.flush if @pipe_out and !@pipe_out.closed?
    end

    def terminate
      begin
	@pipe_in.close
      rescue IOError
      end
      begin
	@pipe_out.close
      rescue IOError
      end
    end

    def kill(sig)
      if @pid
	Process.kill(sig, @pid)
      end
    end


    def start_import
#      Thread.critical = true
      notify "Job(%id) start imp-pipe.", @shell.debug?
      rs = @shell.record_separator unless rs
      _eop = true
#      Thread.critical = false
      th = Thread.start {
	Thread.critical = true
	begin
	  Thread.critical = false
	  while l = @pipe_in.gets
	    @input_queue.push l
	  end
	  _eop = false
	rescue Errno::EPIPE
	  _eop = false
	ensure
	  if _eop
	    notify("warn: Process finishing...",
		   "wait for Job[%id] to finish pipe importing.",
		   "You can use Shell#transact or Shell#check_point for more safe execution.")
#	    Tracer.on
	    Thread.current.run
	    redo
	  end
	  Thread.exclusive do
	    notify "job(%id}) close imp-pipe.", @shell.debug?
	    @input_queue.push :EOF
	    @pipe_in.close
	  end
	end
      }
    end

    def start_export
      notify "job(%id) start exp-pipe.", @shell.debug?
      _eop = true
      th = Thread.start{
	Thread.critical = true
	begin
	  Thread.critical = false
	  @input.each{|l| @pipe_out.print l}
	  _eop = false
	rescue Errno::EPIPE
	  _eop = false
	ensure
	  if _eop
	    notify("shell: warn: Process finishing...",
		   "wait for Job(%id) to finish pipe exporting.",
		   "You can use Shell#transact or Shell#check_point for more safe execution.")
#	    Tracer.on
	    redo
	  end
	  Thread.exclusive do
	    notify "job(%id) close exp-pipe.", @shell.debug?
	    @pipe_out.close
	  end
	end
      }
    end

    alias super_each each
    def each(rs = nil)
      while (l = @input_queue.pop) != :EOF
	yield l
      end
    end

    # ex)
    #    if you wish to output: 
    #	    "shell: job(#{@command}:#{@pid}) close pipe-out."
    #	 then 
    #	    mes: "job(%id) close pipe-out."
    #    yorn: Boolean(@shell.debug? or @shell.verbose?)
    def notify(*opts, &block)
      Thread.exclusive do
	@shell.notify(*opts) {|mes|
	  yield mes if iterator?

	  mes.gsub!("%id", "#{@command}:##{@pid}")
	  mes.gsub!("%name", "#{@command}")
	  mes.gsub!("%pid", "#{@pid}")
	}
      end
    end
  end
end
