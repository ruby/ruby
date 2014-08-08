#   save-history.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

require "readline"

module IRB
  module HistorySavingAbility # :nodoc:
    @RCS_ID='-$Id$-'
  end

  class Context
    def init_save_history# :nodoc:
      unless (class<<@io;self;end).include?(HistorySavingAbility)
        @io.extend(HistorySavingAbility)
      end
    end

    # A copy of the default <code>IRB.conf[:SAVE_HISTORY]</code>
    def save_history
      IRB.conf[:SAVE_HISTORY]
    end

    # Sets <code>IRB.conf[:SAVE_HISTORY]</code> to the given +val+ and calls
    # #init_save_history with this context.
    #
    # Will store the number of +val+ entries of history in the #history_file
    #
    # Add the following to your +.irbrc+ to change the number of history
    # entries stored to 1000:
    #
    #     IRB.conf[:SAVE_HISTORY] = 1000
    def save_history=(val)
      IRB.conf[:SAVE_HISTORY] = val
      if val
        main_context = IRB.conf[:MAIN_CONTEXT]
        main_context = self unless main_context
        main_context.init_save_history
      end
    end

    # A copy of the default <code>IRB.conf[:HISTORY_FILE]</code>
    def history_file
      IRB.conf[:HISTORY_FILE]
    end

    # Set <code>IRB.conf[:HISTORY_FILE]</code> to the given +hist+.
    def history_file=(hist)
      IRB.conf[:HISTORY_FILE] = hist
    end
  end

  module HistorySavingAbility # :nodoc:
    include Readline

#     def HistorySavingAbility.create_finalizer
#       proc do
# 	if num = IRB.conf[:SAVE_HISTORY] and (num = num.to_i) > 0
# 	  if hf = IRB.conf[:HISTORY_FILE]
# 	    file = File.expand_path(hf)
# 	  end
# 	  file = IRB.rc_file("_history") unless file
# 	  open(file, 'w' ) do |f|
# 	    hist = HISTORY.to_a
# 	    f.puts(hist[-num..-1] || hist)
# 	  end
# 	end
#       end
#     end

    def HistorySavingAbility.extended(obj)
#      ObjectSpace.define_finalizer(obj, HistorySavingAbility.create_finalizer)
      IRB.conf[:AT_EXIT].push proc{obj.save_history}
      obj.load_history
      obj
    end

    def load_history
      if history_file = IRB.conf[:HISTORY_FILE]
        history_file = File.expand_path(history_file)
      end
      history_file = IRB.rc_file("_history") unless history_file
      if File.exist?(history_file)
        open(history_file) do |f|
          f.each {|l| HISTORY << l.chomp}
        end
      end
    end

    def save_history
      if num = IRB.conf[:SAVE_HISTORY] and (num = num.to_i) > 0
        if history_file = IRB.conf[:HISTORY_FILE]
          history_file = File.expand_path(history_file)
        end
        history_file = IRB.rc_file("_history") unless history_file

        # Change the permission of a file that already exists[BUG #7694]
        begin
          if File.stat(history_file).mode & 066 != 0
            File.chmod(0600, history_file)
          end
        rescue Errno::ENOENT
        rescue
          raise
        end

        open(history_file, 'w', 0600 ) do |f|
          hist = HISTORY.to_a
          f.puts(hist[-num..-1] || hist)
        end
      end
    end
  end
end
