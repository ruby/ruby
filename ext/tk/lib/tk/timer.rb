#
#   tk/timer.rb : methods for Tcl/Tk after command
#
#   $Id$
#
require 'tk'

class TkTimer
  include TkCore
  extend TkCore

  TkCommandNames = ['after'.freeze].freeze

  Tk_CBID = ['a'.freeze, '00000'.taint].freeze
  Tk_CBTBL = {}.taint

  TkCore::INTERP.add_tk_procs('rb_after', 'id', <<-'EOL')
    if {[set st [catch {eval {ruby_cmd TkTimer callback} $id} ret]] != 0} {
        return -code $st $ret
    } {
        return $ret
    }
  EOL

  DEFAULT_IGNORE_EXCEPTIONS = [ NameError, RuntimeError ].freeze

  ###############################
  # class methods
  ###############################
  def self.callback(obj_id)
    ex_obj = Tk_CBTBL[obj_id]
    return "" if ex_obj == nil; # canceled
    ex_obj.cb_call
  end

  def self.info(obj = nil)
    if obj
      if obj.kind_of?(TkTimer)
        if obj.after_id
          inf = tk_split_list(tk_call_without_enc('after','info',obj.after_id))
          [Tk_CBTBL[inf[0][1]], inf[1]]
        else
          nil
        end
      else
        fail ArgumentError, "TkTimer object is expected"
      end
    else
      tk_call_without_enc('after', 'info').split(' ').collect!{|id|
        ret = Tk_CBTBL.find{|key,val| val.after_id == id}
        (ret == nil)? id: ret[1]
      }
    end
  end

  ###############################
  # instance methods
  ###############################
  def do_callback
    @in_callback = true
    @after_id = nil
    begin
      @return_value = @current_proc.call(self)
    rescue SystemExit
      exit(0)
    rescue Interrupt
      exit!(1)
    rescue Exception => e
      if @cancel_on_exception && 
          @cancel_on_exception.find{|exc| e.kind_of?(exc)}
        cancel
        @return_value = e
        @in_callback = false
        return e
      else
        fail e
      end
    end
    if @set_next
      set_next_callback(@current_args)
    else
      @set_next = true
    end
    @in_callback = false
    @return_value
  end

  def set_callback(sleep, args=nil)
    if TkCore::INTERP.deleted?
      self.cancel
      return self
    end
    @after_script = "rb_after #{@id}"
    @after_id = tk_call_without_enc('after', sleep, @after_script)
    @current_args = args
    @current_script = [sleep, @after_script]
    self
  end

  def set_next_callback(args)
    if @running == false || @proc_max == 0 || @do_loop == 0
      Tk_CBTBL.delete(@id) ;# for GC
      @running = false
      @wait_var.value = 0
      return
    end
    if @current_pos >= @proc_max
      if @do_loop < 0 || (@do_loop -= 1) > 0
        @current_pos = 0
      else
        Tk_CBTBL.delete(@id) ;# for GC
        @running = false
        @wait_var.value = 0
        return
      end
    end

    @current_args = args

    if @sleep_time.kind_of? Proc
      sleep = @sleep_time.call(self)
    else
      sleep = @sleep_time
    end
    @current_sleep = sleep

    cmd, *cmd_args = @loop_proc[@current_pos]
    @current_pos += 1
    @current_proc = cmd

    set_callback(sleep, cmd_args)
  end

  def initialize(*args)
    # @id = Tk_CBID.join('')
    @id = Tk_CBID.join(TkCore::INTERP._ip_id_)
    Tk_CBID[1].succ!

    @wait_var = TkVariable.new(0)

    @cb_cmd = TkCore::INTERP.get_cb_entry(self.method(:do_callback))

    @set_next = true

    @init_sleep = 0
    @init_proc = nil
    @init_args = []

    @current_script = []
    @current_proc = nil
    @current_args = nil
    @return_value = nil

    @sleep_time = 0
    @current_sleep = 0
    @loop_exec = 0
    @do_loop = 0
    @loop_proc = []
    @proc_max = 0
    @current_pos = 0

    @after_id = nil
    @after_script = nil

    @cancel_on_exception = DEFAULT_IGNORE_EXCEPTIONS
    # Unless @cancel_on_exception, Ruby/Tk shows an error dialog box when 
    # an excepsion is raised on TkTimer callback procedure. 
    # If @cancel_on_exception is an array of exception classes and the raised 
    # exception is included in the array, Ruby/Tk cancels executing TkTimer 
    # callback procedures silently (TkTimer#cancel is called and no dialog is 
    # shown). 

    set_procs(*args) if args != []

    @running = false
    @in_callback = false
  end

  attr :after_id
  attr :after_script
  attr :current_proc
  attr :current_args
  attr :current_sleep
  alias :current_interval :current_sleep
  attr :return_value

  attr_accessor :loop_exec

  def cb_call
    @cb_cmd.call
  end

  def get_procs
    [@init_sleep, @init_proc, @init_args, @sleep_time, @loop_exec, @loop_proc]
  end

  def current_status
    [@running, @current_sleep, @current_proc, @current_args, 
      @do_loop, @cancel_on_exception]
  end

  def cancel_on_exception?
    @cancel_on_exception
  end

  def cancel_on_exception=(mode)
    if mode.kind_of?(Array)
      @cancel_on_exception = mode
    elsif mode
      @cancel_on_exception = DEFAULT_IGNORE_EXCEPTIONS
    else
      @cancel_on_exception = false
    end
    #self
  end

  def running?
    @running
  end

  def loop_rest
    @do_loop
  end

  def loop_rest=(rest)
    @do_loop = rest
    #self
  end

  def set_procs(interval, loop_exec, *procs)
    if !interval == 'idle' \
       && !interval.kind_of?(Integer) && !interval.kind_of?(Proc)
      fail ArguemntError, "expect Integer or Proc for 1st argument"
    end
    @sleep_time = interval

    @loop_proc = []
    procs.each{|e|
      if e.kind_of? Proc
        @loop_proc.push([e])
      else
        @loop_proc.push(e)
      end
    }
    @proc_max = @loop_proc.size
    @current_pos = 0

    @do_loop = 0
    if loop_exec
      if loop_exec.kind_of?(Integer) && loop_exec < 0
        @loop_exec = -1
      elsif loop_exec == nil || loop_exec == false || loop_exec == 0
        @loop_exec = 1
      else
        if not loop_exec.kind_of?(Integer)
          fail ArguemntError, "expect Integer for 2nd argument"
        end
        @loop_exec = loop_exec
      end
      @do_loop = @loop_exec
    end

    self
  end

  def add_procs(*procs)
    procs.each{|e|
      if e.kind_of? Proc
        @loop_proc.push([e])
      else
        @loop_proc.push(e)
      end
    }
    @proc_max = @loop_proc.size

    self
  end

  def delete_procs(*procs)
    procs.each{|e|
      if e.kind_of? Proc
        @loop_proc.delete([e])
      else
        @loop_proc.delete(e)
      end
    }
    @proc_max = @loop_proc.size

    cancel if @proc_max == 0

    self
  end

  def delete_at(n)
    @loop_proc.delete_at(n)
    @proc_max = @loop_proc.size
    cancel if @proc_max == 0
    self
  end

  def set_start_proc(sleep, init_proc=nil, *init_args)
    if !sleep == 'idle' && !sleep.kind_of?(Integer)
      fail ArguemntError, "expect Integer or 'idle' for 1st argument"
    end
    @init_sleep = sleep
    @init_proc = init_proc
    @init_args = init_args

    @init_proc = proc{|*args| } if @init_sleep > 0 && !@init_proc

    self
  end

  def start(*init_args)
    return nil if @running

    Tk_CBTBL[@id] = self
    @do_loop = @loop_exec
    @current_pos = 0
    @after_id = nil

    @init_sleep = 0
    @init_proc  = nil
    @init_args  = nil

    argc = init_args.size
    if argc > 0
      sleep = init_args.shift
      if !sleep == 'idle' && !sleep.kind_of?(Integer)
        fail ArguemntError, "expect Integer or 'idle' for 1st argument"
      end
      @init_sleep = sleep
    end
    @init_proc = init_args.shift if argc > 1
    @init_args = init_args if argc > 2

    @init_proc = proc{|*args| } if @init_sleep > 0 && !@init_proc

    @current_sleep = @init_sleep
    @running = true
    if @init_proc
      if not @init_proc.kind_of? Proc
        fail ArgumentError, "Argument '#{@init_proc}' need to be Proc"
      end
      @current_proc = @init_proc
      set_callback(@init_sleep, @init_args)
      @set_next = false if @in_callback
    else
      set_next_callback(@init_args)
    end

    self
  end

  def reset(*reset_args)
    restart() if @running

    if @init_proc
      @return_value = @init_proc.call(self)
    else
      @return_value = nil
    end

    @current_pos   = 0
    @current_args  = @init_args
    @set_next = false if @in_callback

    self
  end

  def restart(*restart_args)
    cancel if @running
    if restart_args == []
      start(@init_sleep, @init_proc, *@init_args)
    else
      start(*restart_args)
    end
  end

  def cancel
    @running = false
    @wait_var.value = 0
    tk_call 'after', 'cancel', @after_id if @after_id
    @after_id = nil
    Tk_CBTBL.delete(@id) ;# for GC
    self
  end
  alias stop cancel

  def continue(wait=nil)
    fail RuntimeError, "is already running" if @running
    sleep, cmd = @current_script
    fail RuntimeError, "no procedure to continue" unless cmd
    if wait
      unless wait.kind_of? Integer
        fail ArguemntError, "expect Integer for 1st argument"
      end
      sleep = wait
    end
    Tk_CBTBL[@id] = self
    @running = true
    @after_id = tk_call_without_enc('after', sleep, cmd)
    self
  end

  def skip
    fail RuntimeError, "is not running now" unless @running
    cancel
    Tk_CBTBL[@id] = self
    @running = true
    set_next_callback(@current_args)
    self
  end

  def info
    if @after_id
      inf = tk_split_list(tk_call_without_enc('after', 'info', @after_id))
      [Tk_CBTBL[inf[0][1]], inf[1]]
    else
      nil
    end
  end

  def wait(on_thread = true, check_root = false)
    if $SAFE >= 4
      fail SecurityError, "can't wait timer at $SAFE >= 4"
    end

    unless @running
      if @return_value.kind_of?(Exception)
        fail @return_value 
      else
        return @return_value 
      end
    end

    @wait_var.wait(on_thread, check_root)
    if @return_value.kind_of?(Exception)
      fail @return_value 
    else
      @return_value 
    end
  end
  def eventloop_wait(check_root = false)
    wait(false, check_root)
  end
  def thread_wait(check_root = false)
    wait(true, check_root)
  end
  def tkwait(on_thread = true)
    wait(on_thread, true)
  end
  def eventloop_tkwait
    wait(false, true)
  end
  def thread_tkwait
    wait(true, true)
  end
end

TkAfter = TkTimer
