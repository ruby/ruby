require 'drb/drb'
require 'monitor'

module DRb
  class GWIdConv < DRbIdConv
    def to_obj(ref)
      if Array === ref && ref[0] == :DRbObject
        it = DRbObject.new(nil)
        it.reinit(ref[1], ref[2])
        return it
      end
      super(ref)
    end
  end

  class GW
    include MonitorMixin
    def initialize
      super()
      @hash = {}
    end

    def [](key)
      synchronize do
        @hash[key]
      end
    end

    def []=(key, v)
      synchronize do
        @hash[key] = v
      end
    end
  end

  class DRbObject
    def self._load(s)
      uri, ref = Marshal.load(s)
      if DRb.uri == uri
        return ref ? DRb.to_obj(ref) : DRb.front
      end

      it = self.new(nil)
      it.reinit(DRb.uri, [:DRbObject, uri, ref])
      it
    end

    def _dump(lv)
      if DRb.uri == @uri
        if Array === @ref && @ref[0] == :DRbObject
          Marshal.dump([@ref[1], @ref[2]])
        else
          Marshal.dump([@uri, @ref]) # ??
        end
      else
        Marshal.dump([DRb.uri, [:DRbObject, @uri, @ref]])
      end
    end
  end
end
