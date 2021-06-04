module TimeSpecs

  class SubTime < Time; end

  class MethodHolder
    class << self
      define_method(:now, &Time.method(:now))
      define_method(:new, &Time.method(:new))
    end
  end

  class Timezone
    def initialize(options)
      @offset = options[:offset]
    end

    def local_to_utc(t)
      t - @offset
    end

    def utc_to_local(t)
      t + @offset
    end
  end

  class TimezoneMethodCallRecorder < Timezone
    def initialize(options, &blk)
      super(options)
      @blk = blk
    end

    def local_to_utc(t)
      @blk.call(t)
      super
    end

    def utc_to_local(t)
      @blk.call(t)
      super
    end
  end

  class TimeLikeArgumentRecorder
    def self.result
      arguments = []

      zone = TimeSpecs::TimezoneMethodCallRecorder.new(offset: 0) do |obj|
        arguments << obj
      end

      # ensure timezone's methods are called at least once
      Time.new(2000, 1, 1, 12, 0, 0, zone)

      return arguments[0]
    end
  end

  Z = Struct.new(:offset, :abbr)
  Zone = Struct.new(:std, :dst, :dst_range)
  Zones = {
    "Asia/Colombo" => Zone[Z[5*3600+30*60, "MMT"], nil, nil],
    "Europe/Kiev" => Zone[Z[2*3600, "EET"], Z[3*3600, "EEST"], 4..10],
    "PST" => Zone[Z[(-9*60*60), "PST"], nil, nil],
  }

  class TimezoneWithName < Timezone
    attr_reader :name

    def initialize(options)
      @name = options[:name]
      @std, @dst, @dst_range = *Zones[@name]
    end

    def dst?(t)
      @dst_range&.cover?(t.mon)
    end

    def zone(t)
      (dst?(t) ? @dst : @std)
    end

    def utc_offset(t)
      zone(t)&.offset || 0
    end

    def abbr(t)
      zone(t)&.abbr
    end

    def local_to_utc(t)
      t - utc_offset(t)
    end

    def utc_to_local(t)
      t + utc_offset(t)
    end
  end

  class TimeWithFindTimezone < Time
    def self.find_timezone(name)
      TimezoneWithName.new(name: name.to_s)
    end
  end

  TimezoneWithAbbr = TimezoneWithName
end
