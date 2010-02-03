require 'dl'
require 'dl/closure'
require 'thread'

module DL
  SEM = Mutex.new

  CdeclCallbackProcs = {}
  CdeclCallbackAddrs = {}

  def set_callback_internal(proc_entry, addr_entry, argc, ty, abi = DL::Function::DEFAULT, &cbp)
    if( argc < 0 )
      raise(ArgumentError, "arity should not be less than 0.")
    end

    closure = DL::Closure::BlockCaller.new(ty, [TYPE_VOIDP] * argc, abi, &cbp)
    proc_entry[closure.to_i] = closure
    closure.to_i
  end

  def set_cdecl_callback(ty, argc, &cbp)
    set_callback_internal(CdeclCallbackProcs, CdeclCallbackAddrs, argc, ty, &cbp)
  end

  def set_stdcall_callback(ty, argc, &cbp)
    set_callback_internal(StdcallCallbackProcs, StdcallCallbackAddrs, argc, ty, DL::Function::STDCALL, &cbp)
  end

  def remove_callback_internal(proc_entry, addr_entry, addr, ctype = nil)
    addr = addr.to_i
    return false unless proc_entry.key?(addr)
    proc_entry.delete(addr)
    true
  end

  def remove_cdecl_callback(addr, ctype = nil)
    remove_callback_internal(CdeclCallbackProcs, CdeclCallbackAddrs, addr, ctype)
  end

  def remove_stdcall_callback(addr, ctype = nil)
    remove_callback_internal(StdcallCallbackProcs, StdcallCallbackAddrs, addr, ctype)
  end

  alias set_callback set_cdecl_callback
  alias remove_callback remove_cdecl_callback
end
