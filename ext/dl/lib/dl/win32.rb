# -*- ruby -*-

require 'dl'

class Win32API
  DLL = {}

  def initialize(dllname, func, import, export = "0")
    prototype = (export + import.to_s).tr("VPpNnLlIi", "0SSI")
    handle = DLL[dllname] ||= DL::Handle.new(dllname)
    begin
      @sym = handle.sym(func, prototype)
    rescue RuntimeError
      @sym = handle.sym(func + "A", prototype)
    end
  end

  def call(*args)
    import = @sym.proto[1..-1] || ""
    args.each_with_index do |x, i|
      args[i] = nil if x == 0 and import[i] == ?S
      args[i], = [x].pack("I").unpack("i") if import[i] == ?I
    end
    ret, = @sym.call(*args)
    return ret || 0
  end

  alias Call call
end
