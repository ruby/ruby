#
# tk/pack.rb : control pack geometry manager
#
require 'tk'

module TkPack
  include Tk
  extend Tk

  TkCommandNames = ['pack'.freeze].freeze

  def configure(win, *args)
    if args[-1].kind_of?(Hash)
      opts = args.pop
    else
      opts = {}
    end
    params = []
    # params.push((win.kind_of?(TkObject))? win.epath: win)
    params.push(_epath(win))
    args.each{|win|
      # params.push((win.kind_of?(TkObject))? win.epath: win)
      params.push(_epath(win))
    }
    opts.each{|k, v|
      params.push("-#{k}")
      # params.push((v.kind_of?(TkObject))? v.epath: v)
      params.push(_epath(v))
    }
    tk_call_without_enc("pack", 'configure', *params)
  end
  alias pack configure

  def forget(*args)
    return '' if args.size == 0
    wins = args.collect{|win|
      # (win.kind_of?(TkObject))? win.epath: win
      _epath(win)
    }
    tk_call_without_enc('pack', 'forget', *wins)
  end

  def info(slave)
    # slave = slave.epath if slave.kind_of?(TkObject)
    slave = _epath(slave)
    ilist = list(tk_call_without_enc('pack', 'info', slave))
    info = {}
    while key = ilist.shift
      info[key[1..-1]] = ilist.shift
    end
    return info
  end

  def propagate(master, bool=None)
    # master = master.epath if master.kind_of?(TkObject)
    master = _epath(master)
    if bool == None
      bool(tk_call_without_enc('pack', 'propagate', master))
    else
      tk_call_without_enc('pack', 'propagate', master, bool)
    end
  end

  def slaves(master)
    # master = master.epath if master.kind_of?(TkObject)
    master = _epath(master)
    list(tk_call_without_enc('pack', 'slaves', master))
  end

  module_function :pack, :configure, :forget, :info, :propagate, :slaves
end
=begin
def TkPack(win, *args)
  if args[-1].kind_of?(Hash)
    opts = args.pop
  else
    opts = {}
  end
  params = []
  params.push((win.kind_of?(TkObject))? win.epath: win)
  args.each{|win|
    params.push((win.kind_of?(TkObject))? win.epath: win)
  }
  opts.each{|k, v|
    params.push("-#{k}")
    params.push((v.kind_of?(TkObject))? v.epath: v)
  }
  tk_call_without_enc("pack", *params)
end
=end
