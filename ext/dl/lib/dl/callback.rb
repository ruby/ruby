require 'dl'
require 'thread'

module DL
  SEM = Mutex.new

  def set_callback_internal(proc_entry, addr_entry, argc, ty, &cbp)
    if( argc < 0 )
      raise(ArgumentError, "arity should not be less than 0.")
    end
    addr = nil
    SEM.synchronize{
      ary = proc_entry[ty]
      (0...MAX_CALLBACK).each{|n|
        idx = (n * DLSTACK_SIZE) + argc
        if( ary[idx].nil? )
          ary[idx] = cbp
          addr = addr_entry[ty][idx]
          break
        end
      }
    }
    addr
  end

  def set_cdecl_callback(ty, argc, &cbp)
    set_callback_internal(CdeclCallbackProcs, CdeclCallbackAddrs, argc, ty, &cbp)
  end

  def set_stdcall_callback(ty, argc, &cbp)
    set_callback_internal(StdcallCallbackProcs, StdcallCallbackAddrs, argc, ty, &cbp)
  end

  def remove_callback_internal(proc_entry, addr_entry, addr, ctype = nil)
    index = nil
    if( ctype )
      addr_entry[ctype].each_with_index{|xaddr, idx|
        if( xaddr == addr )
          index = idx
        end
      }
    else
      addr_entry.each{|ty,entry|
        entry.each_with_index{|xaddr, idx|
          if( xaddr == addr )
            index = idx
          end
        }
      }
    end
    if( proc_entry[ctype][index] )
      proc_entry[ctype][index] = nil
      return true
    else
      return false
    end
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
