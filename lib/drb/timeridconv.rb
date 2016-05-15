# frozen_string_literal: false
require 'drb/drb'
require 'monitor'

module DRb

  # Timer id conversion keeps objects alive for a certain amount of time after
  # their last access.  The default time period is 600 seconds and can be
  # changed upon initialization.
  #
  # To use TimerIdConv:
  #
  #  DRb.install_id_conv TimerIdConv.new 60 # one minute

  class TimerIdConv < DRbIdConv
    class TimerHolder2 # :nodoc:
      include MonitorMixin

      class InvalidIndexError < RuntimeError; end

      def initialize(keeping=600)
        super()
        @sentinel = Object.new
        @gc = {}
        @renew = {}
        @keeping = keeping
        @expires = Time.now + @keeping
      end

      def add(obj)
        synchronize do
          rotate
          key = obj.__id__
          @renew[key] = obj
          return key
        end
      end

      def fetch(key, dv=@sentinel)
        synchronize do
          rotate
          obj = peek(key)
          if obj == @sentinel
            return dv unless dv == @sentinel
            raise InvalidIndexError
          end
          @renew[key] = obj # KeepIt
          return obj
        end
      end

      private
      def peek(key)
        synchronize do
          return @renew.fetch(key) { @gc.fetch(key, @sentinel) }
        end
      end

      def rotate
        synchronize do
          return if @expires > Time.now
          @gc = @renew      # GCed
          @renew = {}
          @expires = Time.now + @keeping
        end
      end

      def keeper
        Thread.new do
          loop do
            rotate
            sleep(@keeping)
          end
        end
      end
    end

    # Creates a new TimerIdConv which will hold objects for +keeping+ seconds.
    def initialize(keeping=600)
      @holder = TimerHolder2.new(keeping)
    end

    def to_obj(ref) # :nodoc:
      return super if ref.nil?
      @holder.fetch(ref)
    rescue TimerHolder2::InvalidIndexError
      raise "invalid reference"
    end

    def to_id(obj) # :nodoc:
      return @holder.add(obj)
    end
  end
end

# DRb.install_id_conv(TimerIdConv.new)
