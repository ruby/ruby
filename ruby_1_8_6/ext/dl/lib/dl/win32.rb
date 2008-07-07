# -*- ruby -*-

require 'dl'

class Win32API
  DLL = {}

  def initialize(dllname, func, import, export = "0")
    prototype = (export + import.to_s).tr("VPpNnLlIi", "0SSI").sub(/^(.)0*$/, '\1')
    handle = DLL[dllname] ||= DL::Handle.new(dllname)
    @sym = handle.sym(func, prototype)
  end

  def call(*args)
    import = @sym.proto.split("", 2)[1]
    args.each_with_index do |x, i|
      args[i] = nil if x == 0 and import[i] == ?S
      args[i], = [x].pack("I").unpack("i") if import[i] == ?I
    end
    ret, = @sym.call(*args)
    return ret || 0
  end

  alias Call call
end
