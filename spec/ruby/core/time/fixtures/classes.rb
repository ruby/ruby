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

  class TimezoneWithAbbr < Timezone
    def initialize(options)
      super
      @abbr = options[:abbr]
    end

    def abbr(time)
      @abbr
    end
  end

  class TimezoneWithName < Timezone
    def initialize(options)
      super
      @name = options[:name]
    end

    def name
      @name
    end
  end

  class TimeWithFindTimezone < Time
    def self.find_timezone(name)
      TimezoneWithName.new(name: name.to_s, offset: -10*60*60)
    end
  end
end
