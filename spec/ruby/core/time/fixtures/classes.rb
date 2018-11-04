module TimeSpecs

  class SubTime < Time; end

  class MethodHolder
    class << self
      define_method(:now, &Time.method(:now))
      define_method(:new, &Time.method(:new))
    end
  end

  Timezone = Struct.new(:name, :abbr, :offset)
  class Timezone
    def utc_offset(t = nil)
      offset
    end

    def local_to_utc(t)
      t - utc_offset(t)
    end

    def utc_to_local(t)
      t + utc_offset(t)
    end
  end
end
