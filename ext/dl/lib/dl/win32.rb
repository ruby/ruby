# -*- ruby -*-

require 'dl'

class Win32API
  LIBRARY = {}

  attr_reader :val, :args

  def initialize(lib, func, args, ret)
    LIBRARY[lib] ||= DL.dlopen(lib)
    ty = (ret + args).tr('V','0')
    @sym = LIBRARY[lib].sym(func, ty)
    @__dll__ = LIBRARY[lib].to_i
    @__dllname__ = lib
    @__proc__ = @sym.to_i
    @val = nil
    @args = []
  end

  def call(*args)
    @val,@args = @sym.call(*args)
    return @val
  end
  alias Call call
end
