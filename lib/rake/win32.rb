module Rake

  # Win 32 interface methods for Rake. Windows specific functionality
  # will be placed here to collect that knowledge in one spot.
  module Win32
    class << self
      # True if running on a windows system.
      def windows?
        # assume other DOSish systems are extinct.
        File::ALT_SEPARATOR == '\\'
      end
    end

    class << self
      # The standard directory containing system wide rake files on
      # Win 32 systems. Try the following environment variables (in
      # order):
      #
      # * APPDATA
      # * HOME
      # * HOMEDRIVE + HOMEPATH
      # * USERPROFILE
      #
      # If the above are not defined, retruns the personal folder.
      def win32_system_dir #:nodoc:
        win32_shared_path = ENV['APPDATA']
        if !win32_shared_path or win32_shared_path.empty?
          win32_shared_path = '~'
        end
        File.expand_path('Rake', win32_shared_path)
      end
    end if windows?
  end
end
