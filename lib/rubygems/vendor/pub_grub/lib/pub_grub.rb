require_relative "pub_grub/package"
require_relative "pub_grub/static_package_source"
require_relative "pub_grub/term"
require_relative "pub_grub/version_range"
require_relative "pub_grub/version_constraint"
require_relative "pub_grub/version_union"
require_relative "pub_grub/version_solver"
require_relative "pub_grub/incompatibility"
require_relative 'pub_grub/solve_failure'
require_relative 'pub_grub/failure_writer'
require_relative 'pub_grub/version'

module Gem::PubGrub
  # Minimal logger that doesn't require the 'logger' gem
  class NullLogger
    def info(&block); end
    def debug(&block); end
    def warn(&block); end
    def error(&block); end
  end

  class StderrLogger
    def info(&block)
      $stderr.puts "INFO: #{block.call}" if block
    end

    def debug(&block)
      $stderr.puts "DEBUG: #{block.call}" if block
    end

    def warn(&block)
      $stderr.puts "WARN: #{block.call}" if block
    end

    def error(&block)
      $stderr.puts "ERROR: #{block.call}" if block
    end
  end

  class << self
    attr_writer :logger

    def logger
      @logger || default_logger
    end

    private

    def default_logger
      @logger = $DEBUG ? StderrLogger.new : NullLogger.new
    end
  end
end
