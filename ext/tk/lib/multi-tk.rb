#
#		multi-tk.rb - supports multi Tk interpreters
#			by Hidetoshi NAGAI <nagai@ai.kyutech.ac.jp>

require 'tcltklib'
require 'thread'

################################################
# exceptiopn to treat the return value from IP
class MultiTkIp_OK < Exception
  def self.send(thred, ret=nil)
    thread.raise self.new(ret)
  end

  def initialize(ret=nil)
    super('succeed')
    @return_value = ret
  end

  attr_reader :return_value
  alias value return_value
end
MultiTkIp_OK.freeze

################################################
# methods for construction
class MultiTkIp
  SLAVE_IP_ID = ['slave'.freeze, '00000']

  @@IP_TABLE = {}

  @@INIT_IP_ENV  = [] # table of Procs
  @@ADD_TK_PROCS = [] # table of [name, args, body]

  @@TK_TABLE_LIST = []

  @@TK_CMD_TBL = {}

  ######################################

  @@CB_ENTRY_CLASS = Class.new{|c|
    def initialize(ip, cmd)
      @ip = ip
      @cmd = cmd
    end
    attr_reader :ip, :cmd
    def call(*args)
      begin
	 unless @ip.deleted?
	   @ip.cb_eval(@cmd, *args)
	 end
      rescue TkCallbackBreak, TkCallbackContinue
	fail
      rescue Exception
      end
    end
  }

  ######################################

  def _keys2opts(keys)
    keys.collect{|k,v| "-#{k} #{v}"}.join(' ')
  end
  private :_keys2opts

  def _check_and_return(thread, exception, wait=3)
    # wait to stop the caller thread
    return nil unless thread
    wait.times{
      if thread.stop?
	# ready to send exception
	thread.raise exception
	return thread
      end

      # wait
      Thread.pass
    }

    # unexpected error
    thread.raise RuntimeError, "the thread may not wait for the return value"
    return thread
  end

  def _create_receiver_and_watchdog()
    # command-procedures receiver
    receiver = Thread.new{
      loop do
	thread, cmd, *args = @cmd_queue.deq
	begin
	  ret = cmd.call(*args)
	rescue Exception => e
	  # raise exception
	  _check_and_return(thread, e)
	else
	  # no exception
	  _check_and_return(thread, MultiTkIp_OK.new(ret))
	end
      end
    }

    # watchdog of receiver
    watchdog = Thread.new{
      begin
	receiver.join
      rescue Exception
	# ignore all kind of Exception
      end
      # receiver is dead
      loop do
	thread, cmd, *args = @cmd_queue.deq
	next unless thread
	if thread.alive?
	  if @interp.deleted?
	    thread.raise RuntimeError, 'the interpreter is already deleted'
	  else
	    thread.raise RuntimeError, 
	      'the interpreter no longer receives command procedures'
	  end
	end
      end
    }

    # return threads
    [receiver, watchdog]
  end
  private :_check_and_return, :_create_receiver_and_watchdog

  ######################################

  if self.const_defined? :DEFAULT_MASTER_NAME
    name = DEFAULT_MASTER_NAME.to_s
  else
    name = nil
  end
  if self.const_defined?(:DEFAULT_MASTER_OPTS) &&
      DEFAULT_MASTER_OPTS.kind_of?(Hash)
    keys = DEFAULT_MASTER_OPTS
  else
    keys = {}
  end

  @@DEFAULT_MASTER = self.allocate
  @@DEFAULT_MASTER.instance_eval{
    @tk_windows = {}

    @tk_table_list = []

    @slave_ip_tbl = {}

    unless keys.kind_of? Hash
      fail ArgumentError, "expecting a Hash object for the 2nd argument"
    end

    @interp = TclTkIp.new(name, _keys2opts(keys))
    @ip_name = nil

    @threadgroup  = Thread.current.group

    @cmd_queue = Queue.new

    @cmd_receiver, @receiver_watchdog = _create_receiver_and_watchdog()

    @threadgroup.add @cmd_receiver
    @threadgroup.add @receiver_watchdog

    # NOT enclose @threadgroup for @@DEFAULT_MASTER

    @@IP_TABLE[ThreadGroup::Default] = self
    @@IP_TABLE[@threadgroup] = self
  }
  @@DEFAULT_MASTER.freeze # defend against modification

  ######################################

  def self.inherited(subclass)
    # trust if on ThreadGroup::Default or @@DEFAULT_MASTER's ThreadGroup
    if @@IP_TABLE[Thread.current.group] == @@DEFAULT_MASTER
      begin
	class << subclass
	  self.methods.each{|m|
	    begin
	      unless m == '__id__' || m == '__send__' || m == 'freeze'
		undef_method(m)
	      end
	    rescue Exception
	      # ignore all exceptions
	    end
	  }
	end
      ensure
	subclass.freeze
	fail SecurityError, 
	  "cannot create subclass of MultiTkIp on a untrusted ThreadGroup"
      end
    end
  end

  ######################################

  SAFE_OPT_LIST = ['accessPath', 'statics', 'nested', 'deleteHook']
  def _parse_slaveopts(keys)
    name = nil
    safe = false
    safe_opts = {}
    tk_opts   = {}

    keys.each{|k,v|
      if k.to_s == 'name'
	name = v 
      elsif k.to_s == 'safe'
	safe = v
      elsif SAFE_OPT_LIST.member?(k.to_s)
	safe_opts[k] = v
      else
	tk_opts[k] = v
      end
    }

    [name, safe, safe_opts, tk_opts]
  end
  private :_parse_slaveopts

  def _create_slave_ip_name
    name = SLAVE_IP_ID.join
    SLAVE_IP_ID[1].succ!
    name
  end
  private :_create_slave_ip_name

  ######################################

  def __check_safetk_optkeys(optkeys)
    # based on 'safetk.tcl'
    new_keys = {}
    optkeys.each{|k,v| new_key[k.to_s] = v}

    # check 'display'
    if !new_keys.key?('display')
      begin
	new_keys['display'] = @interp._eval('winfo screen .')
      rescue
	if ENV[DISPLAY]
	  new_keys['display'] = ENV[DISPLAY]
	elsif !new_keys.key?('use')
	  warn "Warning: no screen info or ENV[DISPLAY], so use ':0.0'"
	  new_keys['display'] = ':0.0'
	end
      end
    end

    # check 'use'
    if new_keys.key?('use')
      # given 'use'
      case new_keys['use']
      when TkWindow
	new_keys['use'] = TkWinfo.id(new_keys['use'])
	assoc_display = @interp._eval('winfo screen .')
      when /^\..*/
	new_keys['use'] = @interp._invoke('winfo', 'id', new_keys['use'])
	assoc_display = @interp._invoke('winfo', 'screen', new_keys['use'])
      else
	begin
	  pathname = @interp._invoke('winfo', 'pathname', new_keys['use'])
	  assco_display = @interp._invoke('winfo', 'screen', pathname)
	rescue
	  assoc_display = new_keys['display']
	end
      end

      # match display?
      if assoc_display != new_keys['display']
	if optkeys.keys?(:display) || optkeys.keys?('display')
	  fail RuntimeError, 
	    "conflicting 'display'=>#{new_keys['display']} " + 
	    "and display '#{assoc_display}' on 'use'=>#{new_keys['use']}"
	else
	  new_keys['display'] = assoc_display
	end
      end
    end

    # return
    new_keys
  end
  private :__check_safetk_optkeys

  def __create_safetk_frame(slave_ip, slave_name, app_name, keys)
    # create toplevel widget
    dup_keys = keys.dup
    dup_keys['screen'] = dup_keys.delete('display')
    dup_keys['classname'] = 'SafeTk'
    begin
      top = TkToplevel.new(dup_keys)
    rescue NameError
      fail unless @interp.safe?
      fail SecurityError, "unable create toplevel on the safe interpreter"
    end
    msg = "Untrusted Ruby/Tk applet (#{slave_name})"
    if app_name.kind_of?(String)
      top.title "#{app_name} (#{slave_name})"
    else
      top.title msg
    end

    # procedure to delete slave interpreter
    slave_delete_proc = proc{
      unless slave_ip.deleted?
	if slave_ip._invoke('info', 'command', '.') != ""
	  slave_ip._invoke('destroy', '.')
	  slave_ip.tk_windows.delete('.')
	end
	slave_ip.delete
      end
    }
    tag = TkBindTag.new.bind('Destroy', slave_delete_proc)

    # create control frame
    TkFrame.new(top, :bg=>'red', :borderwidth=>3, :relief=>'ridge') {|fc|
      fc.bindtags = fc.bindtags.unshift(tag)

      TkFrame.new(fc, :bd=>0){|f|
	TkButton.new(f, 
		     :text=>'Delete', :bd=>1, :padx=>2, :pady=>0, 
		     :highlightthickness=>0, :command=>slave_delete_proc
		     ).pack(:side=>:right, :fill=>:both)
	f.pack(:side=>:right, :fill=>:both, :expand=>true)
      }

      TkLabel.new(fc, :text=>msg, :padx=>2, :pady=>0, 
		  :anchor=>:w).pack(:side=>:left, :fill=>:both, :expand=>true)

      fc.pack(:side=>:bottom, :fill=>:x)
    }

    # container frame for slave interpreter
    c = TkFrame.new(top, :container=>true).pack(:fill=>:both, :expand=>true)

    # return container's window id
    TkWinfo.id(c)
  end
  private :__create_safetk_frame

  def __create_safe_slave_obj(safe_opts, app_name, tk_opts)
    # safe interpreter
    # at present, not enough support for '-deleteHook' option
    ip_name = _create_slave_ip_name
    slave_ip = @interp.create_slave(ip_name, true)
    @interp._eval("::safe::interpInit #{ip_name} "+_keys2opts(safe_opts))
    tk_opts = __check_safetk_optkeys(tk_opts)
    unless tk_opts.key?('use')
      tk_opts['use'] = __create_safetk_frame(slave_ip, ip_name, 
					     app_name, tk_opts)
    end
    slave_ip._invoke('set', 'argv0', app_name) if app_name.kind_of?(String)
    @interp._eval("::safe::loadTk #{ip_name} #{_keys2opts(tk_opts)}")
    @slave_ip_tbl[ip_name] = slave_ip
    [slave_ip, ip_name]
  end

  def __create_trusted_slave_obj(name, keys)
    ip_name = _create_slave_ip_name
    slave_ip = @interp.create_slave(ip_name, false)
    slave_ip._invoke('set', 'argv0', name) if name.kind_of?(String)
    slave_ip._invoke('set', 'argv', _keys2opts(keys))
    @interp._invoke('load', '', 'Tk', ip_name)
    @slave_ip_tbl[ip_name] = slave_ip
    [slave_ip, ip_name]
  end

  ######################################

  def _create_slave_object(keys={})
    ip = MultiTkIp.new_slave(self, keys={})
    @slave_ip_tbl[ip.name] = ip
  end

  ######################################

  def initialize(master, safeip=true, keys={})
    if safeip == nil && !master.master?
      fail SecurityError, "slave-ip cannot create master-ip"
    end

    unless keys.kind_of? Hash
      fail ArgumentError, "expecting a Hash object for the 2nd argument"
    end

    @tk_windows = {}

    @tk_table_list = []

    @slave_ip_tbl = {}

    name, safe, safe_opts, tk_opts = _parse_slaveopts(keys)

    if safeip == nil
      # create master-ip
      @interp = TclTkIp.new(name, _keys2opts(tk_opts))
      @ip_name = nil
    else
      # create slave-ip
      if safeip || master.safe?
	@interp, @ip_name = master.__create_safe_slave_obj(safe_opts, 
							   name, tk_opts)
      else
	@interp, @ip_name = master.__create_trusted_slave_obj(name, tk_opts)
      end
      @set_alias_proc = proc{|name| 
	master._invoke('interp', 'alias', @ip_name, name, '', name)
      }.freeze
    end

    @threadgroup  = ThreadGroup.new

    @cmd_queue = Queue.new

    @cmd_receiver, @receiver_watchdog = _create_receiver_and_watchdog()

    @threadgroup.add @cmd_receiver
    @threadgroup.add @receiver_watchdog

    @threadgroup.enclose

    @@IP_TABLE[@threadgroup] = self
    _init_ip_internal(@@INIT_IP_ENV, @@ADD_TK_PROCS)
    @@TK_TABLE_LIST.size.times{ @tk_table_list << {} }

    self.freeze  # defend against modification
  end
end


# get target IP
class MultiTkIp
  def self.__getip
    if Thread.current.group == ThreadGroup::Default
      @@DEFAULT_MASTER
    else
      ip = @@IP_TABLE[Thread.current.group]
      unless ip
	fail SecurityError, 
	  "cannot call Tk methods on #{Thread.current.inspect}"
      end
      ip
    end
  end
end


# aliases of constructor
class << MultiTkIp
  alias __new new
  private :__new

  def new_master(keys={})
    __new(__getip, nil, keys)
  end

  alias new new_master

  def new_slave(keys={})
    __new(__getip, false, keys)
  end
  alias new_trusted_slave new_master

  def new_safe_slave(keys={})
    __new(__getip, true, keys)
  end
  alias new_safeTk new_safe_slave
end


# get info
class MultiTkIp
  def inspect
    s = self.to_s.chop!
    if master?
      s << ':master'
    else
      if @interp.safe?
	s << ':safe-slave'
      else
	s << ':trusted-slave'
      end
    end
    s << '>'
  end

  def master?
    if @ip_name
      false
    else
      true
    end
  end

  def slave?
    not master?
  end

  def alive?
    return false unless @cmd_receiver.alive?
    return false if @interp.deleted?
  end

  def path
    @ip_name
  end

  def slaves(all = false)
    @interp._invoke('interp','slaves').split.map!{|name| 
      if @slave_ip_tbl.key?(name)
	@slave_ip_tbl[name]
      elsif all
	name
      else
	nil
      end
    }.compact!
  end
end


# instance methods to treat tables
class MultiTkIp
  def _tk_cmd_tbl
    MultiTkIp.tk_cmd_tbl.collect{|ent| ent.ip == self }
  end

  def _tk_windows
    @tk_windows
  end

  def _tk_table_list
    @tk_table_list
  end

  def _init_ip_env(script)
    script.call(self)
  end

  def _add_tk_procs(name, args, body)
    return if slave?
    @interp._invoke('proc', name, args, body) if args && body
    @interp._invoke('interp', 'slaves').split.each{|slave|
      @interp._invoke('interp', 'alias', slave, name, '', name)
    }
  end

  def _init_ip_internal(init_ip_env, add_tk_procs)
    init_ip_env.each{|script| script.call(self)}
    add_tk_procs.each{|name, args, body| 
      if master?
	@interp._invoke('proc', name, args, body) if args && body
      else
	@set_alias_proc.call(name)
      end
    }
  end
end


# class methods to treat tables
class MultiTkIp
  def self.tk_cmd_tbl
    @@TK_CMD_TBL
  end
  def self.tk_windows
    __getip._tk_windows
  end
  def self.tk_object_table(id)
    __getip._tk_table_list[id]
  end
  def self.create_table
    id = @@TK_TABLE_LIST.size
    @@IP_TABLE.each{|tg, ip| 
      ip.instance_eval{@tk_table_list << {}}
    }
    obj = Object.new
    @@TK_TABLE_LIST << obj
    obj.instance_eval <<-EOD
      def self.method_missing(m, *args)
	 MultiTkIp.tk_object_table(#{id}).send(m, *args)
      end
    EOD
    obj.freeze
    return obj
  end

  def self.init_ip_env(script = Proc.new)
    @@INIT_IP_ENV << script
    @@IP_TABLE.each{|tg, ip| 
      ip._init_ip_env(script)
    }
  end

  def self.add_tk_procs(name, args=nil, body=nil)
    @@ADD_TK_PROCS << [name, args, body]
    @@IP_TABLE.each{|tg, ip| 
      ip._add_tk_procs(name, args, body)
    }
  end

  def self.init_ip_internal
    __getip._init_ip_internal(@@INIT_IP_ENV, @@ADD_TK_PROCS)
  end
end


# for callback operation
class MultiTkIp
  def self.get_cb_entry(cmd)
    @@CB_ENTRY_CLASS.new(__getip, cmd).freeze
  end

  def cb_eval(cmd, *args)
    self.eval_callback{ TkComm._get_eval_string(TkUtil.eval_cmd(cmd, *args)) }
  end
end


# evaluate a procedure on the proper interpreter
class MultiTkIp
  # instance method
  def eval_proc_core(req_val=true, cmd = Proc.new, *args)
    # cmd string ==> proc
    if cmd.kind_of?(String)
      cmd = proc{ TkComm._get_eval_string(TkUtil.eval_cmd(cmd, *args)) }
      args = []
    end

    # on IP thread
    if (@cmd_receiver == Thread.current)
      return cmd.call(*args)
    end
    
    # send cmd to the proc-queue
    if req_val
      @cmd_queue.enq([Thread.current, cmd, *args])
    else
      @cmd_queue.enq([nil, cmd, *args])
      return nil
    end

    # wait and get return value by exception
    begin
      Thread.stop
    rescue MultiTkIp_OK => ret
      # return value
      return ret.value
    end
  end
  private :eval_proc_core

  def eval_callback(cmd = Proc.new, *args)
    eval_proc_core(false, cmd, *args)
  end

  def eval_proc(cmd = Proc.new, *args)
    eval_proc_core(true, cmd, *args)
  end
  alias call eval_proc

  # class method
  def self.eval_proc(cmd = Proc.new, *args)
    # class ==> interp object
    __getip.eval_proc(cmd, *args)
  end
end


# depend on TclTkLib
# all master/slave IPs are controled by only one event-loop
class << MultiTkIp
  def mainloop(check_root = true)
    TclTkLib.mainloop(check_root)
  end
  def mainloop_watchdog(check_root = true)
    TclTkLib.mainloop_watchdog(check_root)
  end
  def do_one_event(flag = TclTkLib::EventFlag::ALL)
    TclTkLib.do_one_event(flag)
  end
  def set_eventloop_tick(tick)
    TclTkLib.set_eventloop_tick(tick)
  end
  def get_eventloop_tick
    TclTkLib.get_eventloop_tick
  end
  def set_no_event_wait(tick)
    TclTkLib.set_no_event_wait(tick)
  end
  def get_no_event_wait
    TclTkLib.get_no_event_wait
  end
  def set_eventloop_weight(loop_max, no_event_tick)
    TclTkLib.set_eventloop_weight(loop_max, no_event_tick)
  end
  def get_eventloop_weight
    TclTkLib.get_eventloop_weight
  end
end


# class methods to delegate to TclTkIp
class << MultiTkIp
  def make_safe
    __getip.make_safe
  end

  def safe?
    __getip.safe?
  end

  def restart
    __getip.restart
  end

  def _eval(str)
    __getip._eval(str)
  end

  def _invoke(*args)
    __getip._invoke(*args)
  end

  def _toUTF8(str, encoding)
    __getip._toUTF8(str, encoding)
  end

  def _fromUTF8(str, encoding)
    __getip._fromUTF8(str, encoding)
  end

  def _return_value
    __getip._return_value
  end
end


# depend on TclTkIp
class MultiTkIp
  def make_safe
    @interp.make_safe
  end

  def safe?
    @interp.safe?
  end

  def delete
    @interp.delete
  end

  def deleted?
    @interp.deleted?
  end

  def restart
    @interp.restart
  end

  def _eval(str)
    @interp._eval(str)
  end

  def _invoke(*args)
    @interp._invoke(*args)
  end

  def _toUTF8(str, encoding)
    @interp._toUTF8(str, encoding)
  end

  def _fromUTF8(str, encoding)
    @interp._fromUTF8(str, encoding)
  end

  def _return_value
    @interp._return_value
  end
end


# end of MultiTkIp definition

MultiTkIp.freeze # defend against modification


########################################
#  start Tk which depends on MultiTkIp
module TkCore
  INTERP = MultiTkIp
end
require 'tk'
