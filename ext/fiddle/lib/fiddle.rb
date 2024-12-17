# frozen_string_literal: true

if RUBY_ENGINE == 'ruby'
  require 'fiddle.so'
else
  require 'fiddle/ffi_backend'
end
require 'fiddle/closure'
require 'fiddle/function'
require 'fiddle/version'

module Fiddle
  if WINDOWS
    # Returns the last win32 +Error+ of the current executing +Thread+ or nil
    # if none
    def self.win32_last_error
      if RUBY_ENGINE == 'jruby'
        errno = FFI.errno
        errno == 0 ? nil : errno
      else
        Thread.current[:__FIDDLE_WIN32_LAST_ERROR__]
      end
    end

    # Sets the last win32 +Error+ of the current executing +Thread+ to +error+
    def self.win32_last_error= error
      if RUBY_ENGINE == 'jruby'
        FFI.errno = error || 0
      else
        Thread.current[:__FIDDLE_WIN32_LAST_ERROR__] = error
      end
    end

    # Returns the last win32 socket +Error+ of the current executing
    # +Thread+ or nil if none
    def self.win32_last_socket_error
      if RUBY_ENGINE == 'jruby'
        errno = FFI.errno
        errno == 0 ? nil : errno
      else
        Thread.current[:__FIDDLE_WIN32_LAST_SOCKET_ERROR__]
      end
    end

    # Sets the last win32 socket +Error+ of the current executing
    # +Thread+ to +error+
    def self.win32_last_socket_error= error
      if RUBY_ENGINE == 'jruby'
        FFI.errno = error || 0
      else
        Thread.current[:__FIDDLE_WIN32_LAST_SOCKET_ERROR__] = error
      end
    end
  end

  # Returns the last +Error+ of the current executing +Thread+ or nil if none
  def self.last_error
    if RUBY_ENGINE == 'jruby'
      errno = FFI.errno
      errno == 0 ? nil : errno
    else
      Thread.current[:__FIDDLE_LAST_ERROR__]
    end
  end

  # Sets the last +Error+ of the current executing +Thread+ to +error+
  def self.last_error= error
    if RUBY_ENGINE == 'jruby'
      FFI.errno = error || 0
    else
      Thread.current[:__DL2_LAST_ERROR__] = error
      Thread.current[:__FIDDLE_LAST_ERROR__] = error
    end
  end

  # call-seq: dlopen(library) => Fiddle::Handle
  #
  # Creates a new handler that opens +library+, and returns an instance of
  # Fiddle::Handle.
  #
  # If +nil+ is given for the +library+, Fiddle::Handle::DEFAULT is used, which
  # is the equivalent to RTLD_DEFAULT. See <code>man 3 dlopen</code> for more.
  #
  #   lib = Fiddle.dlopen(nil)
  #
  # The default is dependent on OS, and provide a handle for all libraries
  # already loaded. For example, in most cases you can use this to access
  # +libc+ functions, or ruby functions like +rb_str_new+.
  #
  # See Fiddle::Handle.new for more.
  def dlopen library
    begin
      Fiddle::Handle.new(library)
    rescue DLError => error
      case RUBY_PLATFORM
      when /linux/
        case error.message
        when /\A(\/.+?): (?:invalid ELF header|file too short)/
          # This may be a linker script:
          # https://sourceware.org/binutils/docs/ld.html#Scripts
          path = $1
        else
          raise
        end
      else
        raise
      end

      File.open(path) do |input|
        input.each_line do |line|
          case line
          when /\A\s*(?:INPUT|GROUP)\s*\(\s*([^\s,\)]+)/
            # TODO: Should we support multiple files?
            first_input = $1
            if first_input.start_with?("-l")
              first_input = "lib#{first_input[2..-1]}.so"
            end
            return dlopen(first_input)
          end
        end
      end

      # Not found
      raise
    end
  end
  module_function :dlopen

  # Add constants for backwards compat

  RTLD_GLOBAL = Handle::RTLD_GLOBAL # :nodoc:
  RTLD_LAZY   = Handle::RTLD_LAZY   # :nodoc:
  RTLD_NOW    = Handle::RTLD_NOW    # :nodoc:

  Fiddle::Types.constants.each do |type|
    const_set "TYPE_#{type}", Fiddle::Types.const_get(type)
  end
end
