#
#   shell/process-controller.rb - 
#   	$Release Version: 0.6.0 $
#   	$Revision: 1.3 $
#   	$Date: 2003/10/16 17:47:19 $
#   	by Keiju ISHITSUKA(Nihon Rational Software Co.,Ltd)
#
# --
#
#   
#

require "mutex_m"
require "monitor"
require "sync"

class Shell
  class ProcessController

    @ProcessControllers = {}
    @ProcessControllers.extend Mutex_m

    class<<self

      def process_controllers_exclusive
	begin
	  @ProcessControllers.lock unless Thread.critical 
	  yield
	ensure
	  @ProcessControllers.unlock unless Thread.critical 
	end
      end

      def activate(pc)
	process_controllers_exclusive do
	  @ProcessControllers[pc] ||= 0
	  @ProcessControllers[pc] += 1
	end
      end

      def inactivate(pc)
	process_controllers_exclusive do
	  if @ProcessControllers[pc]
	    if (@ProcessControllers[pc] -= 1) == 0
	      @ProcessControllers.delete(pc)
	    end
	  end
	end
      end

      def each_active_object
	process_controllers_exclusive do
	  for ref in @ProcessControllers.keys
	    yield ref
	  end
	end
      end
    end

    def initialize(shell)
      @shell = shell
      @waiting_jobs = []
      @active_jobs = []
      @jobs_sync = Sync.new

      @job_monitor = Mutex.new
      @job_condition = ConditionVariable.new
    end

    def jobs
      jobs = []
      @jobs_sync.synchronize(:SH) do
	jobs.concat @waiting_jobs
	jobs.concat @active_jobs
      end
      jobs
    end

    def active_jobs
      @active_jobs
    end

    def waiting_jobs
      @waiting_jobs
    end
    
    def jobs_exist?
      @jobs_sync.synchronize(:SH) do
	@active_jobs.empty? or @waiting_jobs.empty?
      end
    end

    def active_jobs_exist?
      @jobs_sync.synchronize(:SH) do
	@active_jobs.empty?
      end
    end

    def waiting_jobs_exist?
      @jobs_sync.synchronize(:SH) do
	@waiting_jobs.empty?
      end
    end

    # schedule a command
    def add_schedule(command)
      @jobs_sync.synchronize(:EX) do
	ProcessController.activate(self)
	if @active_jobs.empty?
	  start_job command
	else
	  @waiting_jobs.push(command)
	end
      end
    end

    # start a job
    def start_job(command = nil)
      @jobs_sync.synchronize(:EX) do
	if command
	  return if command.active?
	  @waiting_jobs.delete command
	else
	  command = @waiting_jobs.shift
	  return unless command
	end
	@active_jobs.push command
	command.start

	# start all jobs that input from the job
	for job in @waiting_jobs
	  start_job(job) if job.input == command
	end
      end
    end

    def waiting_job?(job)
      @jobs_sync.synchronize(:SH) do
	@waiting_jobs.include?(job)
      end
    end

    def active_job?(job)
      @jobs_sync.synchronize(:SH) do
	@active_jobs.include?(job)
      end
    end

    # terminate a job
    def terminate_job(command)
      @jobs_sync.synchronize(:EX) do
	@active_jobs.delete command
	ProcessController.inactivate(self)
	if @active_jobs.empty?
	  start_job
	end
      end
    end

    # kill a job
    def kill_job(sig, command)
      @jobs_sync.synchronize(:SH) do
	if @waiting_jobs.delete command
	  ProcessController.inactivate(self)
	  return
	elsif @active_jobs.include?(command)
	  begin
	    r = command.kill(sig)
	    ProcessController.inactivate(self)
	  rescue
	    print "Shell: Warn: $!\n" if @shell.verbose?
	    return nil
	  end
	  @active_jobs.delete command
	  r
	end
      end
    end

    # wait for all jobs to terminate
    def wait_all_jobs_execution
      @job_monitor.synchronize do
	begin
	  while !jobs.empty?
	    @job_condition.wait(@job_monitor)
	  end
	ensure
	  redo unless jobs.empty?
	end
      end
    end

    # simple fork
    def sfork(command, &block)
      pipe_me_in, pipe_peer_out = IO.pipe
      pipe_peer_in, pipe_me_out = IO.pipe
      Thread.critical = true

      STDOUT.flush
      ProcessController.each_active_object do |pc|
	for jobs in pc.active_jobs
	  jobs.flush
	end
      end
      
      pid = fork {
	Thread.critical = true

	Thread.list.each do |th| 
	  th.kill unless [Thread.main, Thread.current].include?(th)
	end

	STDIN.reopen(pipe_peer_in)
	STDOUT.reopen(pipe_peer_out)

	ObjectSpace.each_object(IO) do |io| 
	  if ![STDIN, STDOUT, STDERR].include?(io)
	    io.close unless io.closed?
	  end
	end
	yield
      }

      pipe_peer_in.close
      pipe_peer_out.close
      command.notify "job(%name:##{pid}) start", @shell.debug?
      Thread.critical = false

      th = Thread.start {
	Thread.critical = true
	begin
	  _pid = nil
	  command.notify("job(%id) start to waiting finish.", @shell.debug?)
	  Thread.critical = false
	  _pid = Process.waitpid(pid, nil)
	rescue Errno::ECHILD
	  command.notify "warn: job(%id) was done already waitipd."
	  _pid = true
	ensure
	  # when the process ends, wait until the command termintes
	  if _pid
	  else
	    command.notify("notice: Process finishing...",
			   "wait for Job[%id] to finish.",
			   "You can use Shell#transact or Shell#check_point for more safe execution.")
	    redo
	  end
	  Thread.exclusive do
	    terminate_job(command)
	    @job_condition.signal
	    command.notify "job(%id) finish.", @shell.debug?
	  end
	end
      }
      return pid, pipe_me_in, pipe_me_out
    end
  end
end
