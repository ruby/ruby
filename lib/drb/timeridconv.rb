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

      def initialize(timeout=600)
        super()
        @sentinel = Object.new
        @gc = {}
        @curr = {}
        @renew = {}
        @timeout = timeout
        @keeper = keeper
      end

      def add(obj)
        synchronize do
          key = obj.__id__
          @curr[key] = obj
          return key
        end
      end

      def fetch(key, dv=@sentinel)
        synchronize do
          obj = peek(key)
          if obj == @sentinel
            return dv unless dv == @sentinel
            raise InvalidIndexError
          end
          @renew[key] = obj # KeepIt
          return obj
        end
      end

      def include?(key)
        synchronize do
          obj = peek(key)
          return false if obj == @sentinel
          true
        end
      end

      def peek(key)
        synchronize do
          return @curr.fetch(key, @renew.fetch(key, @gc.fetch(key, @sentinel)))
        end
      end

      private
      def alternate
        synchronize do
          @gc = @curr       # GCed
          @curr = @renew
          @renew = {}
        end
      end

      def keeper
        Thread.new do
          loop do
            alternate
            sleep(@timeout)
          end
        end
      end
    end

    # Creates a new TimerIdConv which will hold objects for +timeout+ seconds.
    def initialize(timeout=600)
      @holder = TimerHolder2.new(timeout)
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
