require "pathname"

module IRB
  module History
    DEFAULT_ENTRY_LIMIT = 1000

    class << self
      # Integer representation of <code>IRB.conf[:HISTORY_FILE]</code>.
      def save_history
        return 0 if IRB.conf[:SAVE_HISTORY] == false
        return DEFAULT_ENTRY_LIMIT if IRB.conf[:SAVE_HISTORY] == true
        IRB.conf[:SAVE_HISTORY].to_i
      end

      def save_history?
        !save_history.zero?
      end

      def infinite?
        save_history.negative?
      end

      # Might be nil when HOME and XDG_CONFIG_HOME are not available.
      def history_file
        if (history_file = IRB.conf[:HISTORY_FILE])
          File.expand_path(history_file)
        else
          IRB.rc_file("_history")
        end
      end
    end
  end

  module HistorySavingAbility # :nodoc:
    def support_history_saving?
      true
    end

    def reset_history_counter
      @loaded_history_lines = self.class::HISTORY.size
    end

    def load_history
      history_file = History.history_file
      return unless File.exist?(history_file.to_s)

      history = self.class::HISTORY

      File.open(history_file, "r:#{IRB.conf[:LC_MESSAGES].encoding}") do |f|
        f.each { |l|
          l = l.chomp
          if self.class == RelineInputMethod and history.last&.end_with?("\\")
            history.last.delete_suffix!("\\")
            history.last << "\n" << l
          else
            history << l
          end
        }
      end
      @loaded_history_lines = history.size
      @loaded_history_mtime = File.mtime(history_file)
    end

    def save_history
      return unless History.save_history?
      return unless (history_file = History.history_file)
      unless ensure_history_file_writable(history_file)
        warn <<~WARN
          Can't write history to #{History.history_file.inspect} due to insufficient permissions.
          Please verify the value of `IRB.conf[:HISTORY_FILE]`. Ensure the folder exists and that both the folder and file (if it exists) are writable.
        WARN
        return
      end

      history = self.class::HISTORY.to_a

      if File.exist?(history_file) &&
          File.mtime(history_file) != @loaded_history_mtime
        history = history[@loaded_history_lines..-1] if @loaded_history_lines
        append_history = true
      end

      File.open(history_file, (append_history ? "a" : "w"), 0o600, encoding: IRB.conf[:LC_MESSAGES]&.encoding) do |f|
        hist = history.map { |l| l.scrub.split("\n").join("\\\n") }

        unless append_history || History.infinite?
          # Check size before slicing because array.last(huge_number) raises RangeError.
          hist = hist.last(History.save_history) if hist.size > History.save_history
        end

        f.puts(hist)
      end
    end

    private

    # Returns boolean whether writing to +history_file+ will be possible.
    # Permissions of already existing +history_file+ are changed to
    # owner-only-readable if necessary [BUG #7694].
    def ensure_history_file_writable(history_file)
      history_file = Pathname.new(history_file)

      return false unless history_file.dirname.writable?
      return true unless history_file.exist?

      begin
        if history_file.stat.mode & 0o66 != 0
          history_file.chmod 0o600
        end
        true
      rescue Errno::EPERM # no permissions
        false
      end
    end
  end
end
