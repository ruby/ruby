# frozen_string_literal: true

module Bundler
  # General purpose class for retrying code that may fail
  class Retry
    attr_accessor :name, :total_runs, :current_run

    class << self
      attr_accessor :default_base_delay

      def default_attempts
        default_retries + 1
      end
      alias_method :attempts, :default_attempts

      def default_retries
        Bundler.settings[:retry]
      end
    end

    # Set default base delay for exponential backoff
    self.default_base_delay = 1.0

    def initialize(name, exceptions = nil, retries = self.class.default_retries, opts = {})
      @name = name
      @retries = retries
      @exceptions = Array(exceptions) || []
      @total_runs = @retries + 1 # will run once, then upto attempts.times
      @base_delay = opts[:base_delay] || self.class.default_base_delay
      @max_delay = opts[:max_delay] || 60.0
      @jitter = opts[:jitter] || 0.5
    end

    def attempt(&block)
      @current_run = 0
      @failed      = false
      @error       = nil
      run(&block) while keep_trying?
      @result
    end
    alias_method :attempts, :attempt

    private

    def run(&block)
      @failed = false
      @current_run += 1
      @result = block.call
    rescue StandardError => e
      fail_attempt(e)
    end

    def fail_attempt(e)
      @failed = true
      if last_attempt? || @exceptions.any? {|k| e.is_a?(k) }
        Bundler.ui.info "" unless Bundler.ui.debug?
        raise e
      end
      if name
        Bundler.ui.info "" unless Bundler.ui.debug? # Add new line in case dots preceded this
        Bundler.ui.warn "Retrying #{name} due to error (#{current_run.next}/#{total_runs}): #{e.class} #{e.message}", true
      end
      backoff_sleep if @base_delay > 0
      true
    end

    def backoff_sleep
      # Exponential backoff: delay = base_delay * 2^(attempt - 1)
      # Add jitter to prevent thundering herd: random value between 0 and jitter seconds
      delay = @base_delay * (2**(@current_run - 1))
      delay = [@max_delay, delay].min
      jitter_amount = rand * @jitter
      total_delay = delay + jitter_amount
      Bundler.ui.debug "Sleeping for #{total_delay.round(2)} seconds before retry"
      sleep(total_delay)
    end

    def sleep(duration)
      Kernel.sleep(duration)
    end

    def keep_trying?
      return true  if current_run.zero?
      return false if last_attempt?
      true if @failed
    end

    def last_attempt?
      current_run >= total_runs
    end
  end
end
