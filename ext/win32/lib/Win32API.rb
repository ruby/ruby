# frozen_string_literal: false
# -*- ruby -*-
# for backward compatibility
warn "Warning:#{caller[0].sub(/:in `.*'\z/, '')}: Win32API is deprecated after Ruby 1.9.1; use fiddle directly instead" if $VERBOSE

require 'fiddle/import'

class Win32API
  DLL = {}
  TYPEMAP = {"0" => Fiddle::TYPE_VOID, "S" => Fiddle::TYPE_VOIDP, "I" => Fiddle::TYPE_LONG}
  POINTER_TYPE = Fiddle::SIZEOF_VOIDP == Fiddle::SIZEOF_LONG_LONG ? 'q*' : 'l!*'

  def initialize(dllname, func, import, export = "0", calltype = :stdcall)
    @proto = [import].join.tr("VPpNnLlIi", "0SSI").sub(/^(.)0*$/, '\1')
    handle = DLL[dllname] ||= Fiddle.dlopen(dllname)

    @func = Fiddle::Function.new(
      handle[func],
      @proto.chars.map { |win_type| TYPEMAP[win_type.tr("VPpNnLlIi", "0SSI")] },
      TYPEMAP[export.tr("VPpNnLlIi", "0SSI")],
      Fiddle::Importer.const_get(:CALL_TYPE_TO_ABI)[calltype]
    )
  rescue Fiddle::DLError => e
    raise LoadError, e.message, e.backtrace
  end

  def call(*args)
    import = @proto.split("")
    args.each_with_index do |x, i|
      args[i], = [x == 0 ? nil : x].pack("p").unpack(POINTER_TYPE) if import[i] == "S"
      args[i], = [x].pack("I").unpack("i") if import[i] == "I"
    end
    ret, = @func.call(*args)
    return ret || 0
  end

  alias Call call
end
