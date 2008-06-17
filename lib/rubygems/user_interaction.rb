#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

module Gem

  ##
  # Module that defines the default UserInteraction.  Any class including this
  # module will have access to the +ui+ method that returns the default UI.

  module DefaultUserInteraction

    ##
    # The default UI is a class variable of the singleton class for this
    # module.

    @ui = nil

    ##
    # Return the default UI.

    def self.ui
      @ui ||= Gem::ConsoleUI.new
    end

    ##
    # Set the default UI.  If the default UI is never explicitly set, a simple
    # console based UserInteraction will be used automatically.

    def self.ui=(new_ui)
      @ui = new_ui
    end

    ##
    # Use +new_ui+ for the duration of +block+.

    def self.use_ui(new_ui)
      old_ui = @ui
      @ui = new_ui
      yield
    ensure
      @ui = old_ui
    end

    ##
    # See DefaultUserInteraction::ui

    def ui
      DefaultUserInteraction.ui
    end

    ##
    # See DefaultUserInteraction::ui=

    def ui=(new_ui)
      DefaultUserInteraction.ui = new_ui
    end

    ##
    # See DefaultUserInteraction::use_ui

    def use_ui(new_ui, &block)
      DefaultUserInteraction.use_ui(new_ui, &block)
    end

  end

  ##
  # Make the default UI accessable without the "ui." prefix.  Classes
  # including this module may use the interaction methods on the default UI
  # directly.  Classes may also reference the ui and ui= methods.
  #
  # Example:
  #
  #   class X
  #     include Gem::UserInteraction
  #
  #     def get_answer
  #       n = ask("What is the meaning of life?")
  #     end
  #   end

  module UserInteraction

    include DefaultUserInteraction

    [:alert,
     :alert_error,
     :alert_warning,
     :ask,
     :ask_yes_no,
     :choose_from_list,
     :say,
     :terminate_interaction ].each do |methname|
      class_eval %{
        def #{methname}(*args)
          ui.#{methname}(*args)
        end
      }, __FILE__, __LINE__
    end
  end

  ##
  # StreamUI implements a simple stream based user interface.

  class StreamUI

    attr_reader :ins, :outs, :errs

    def initialize(in_stream, out_stream, err_stream=STDERR)
      @ins = in_stream
      @outs = out_stream
      @errs = err_stream
    end

    ##
    # Choose from a list of options.  +question+ is a prompt displayed above
    # the list.  +list+ is a list of option strings.  Returns the pair
    # [option_name, option_index].

    def choose_from_list(question, list)
      @outs.puts question

      list.each_with_index do |item, index|
        @outs.puts " #{index+1}. #{item}"
      end

      @outs.print "> "
      @outs.flush

      result = @ins.gets

      return nil, nil unless result

      result = result.strip.to_i - 1
      return list[result], result
    end

    ##
    # Ask a question.  Returns a true for yes, false for no.  If not connected
    # to a tty, raises an exception if default is nil, otherwise returns
    # default.

    def ask_yes_no(question, default=nil)
      unless @ins.tty? then
        if default.nil? then
          raise Gem::OperationNotSupportedError,
                "Not connected to a tty and no default specified"
        else
          return default
        end
      end

      qstr = case default
             when nil
               'yn'
             when true
               'Yn'
             else
               'yN'
             end

      result = nil

      while result.nil?
        result = ask("#{question} [#{qstr}]")
        result = case result
        when /^[Yy].*/
          true
        when /^[Nn].*/
          false
        when /^$/
          default
        else
          nil
        end
      end

      return result
    end

    ##
    # Ask a question.  Returns an answer if connected to a tty, nil otherwise.

    def ask(question)
      return nil if not @ins.tty?

      @outs.print(question + "  ")
      @outs.flush

      result = @ins.gets
      result.chomp! if result
      result
    end

    ##
    # Display a statement.

    def say(statement="")
      @outs.puts statement
    end

    ##
    # Display an informational alert.  Will ask +question+ if it is not nil.

    def alert(statement, question=nil)
      @outs.puts "INFO:  #{statement}"
      ask(question) if question
    end

    ##
    # Display a warning in a location expected to get error messages.  Will
    # ask +question+ if it is not nil.

    def alert_warning(statement, question=nil)
      @errs.puts "WARNING:  #{statement}"
      ask(question) if question
    end

    ##
    # Display an error message in a location expected to get error messages.
    # Will ask +question+ if it is not nil.

    def alert_error(statement, question=nil)
      @errs.puts "ERROR:  #{statement}"
      ask(question) if question
    end

    ##
    # Terminate the application with exit code +status+, running any exit
    # handlers that might have been defined.

    def terminate_interaction(status = 0)
      raise Gem::SystemExitException, status
    end

    ##
    # Return a progress reporter object chosen from the current verbosity.

    def progress_reporter(*args)
      case Gem.configuration.verbose
      when nil, false
        SilentProgressReporter.new(@outs, *args)
      when true
        SimpleProgressReporter.new(@outs, *args)
      else
        VerboseProgressReporter.new(@outs, *args)
      end
    end

    ##
    # An absolutely silent progress reporter.

    class SilentProgressReporter
      attr_reader :count

      def initialize(out_stream, size, initial_message, terminal_message = nil)
      end

      def updated(message)
      end

      def done
      end
    end

    ##
    # A basic dotted progress reporter.

    class SimpleProgressReporter
      include DefaultUserInteraction

      attr_reader :count

      def initialize(out_stream, size, initial_message,
                     terminal_message = "complete")
        @out = out_stream
        @total = size
        @count = 0
        @terminal_message = terminal_message

        @out.puts initial_message
      end

      ##
      # Prints out a dot and ignores +message+.

      def updated(message)
        @count += 1
        @out.print "."
        @out.flush
      end

      ##
      # Prints out the terminal message.

      def done
        @out.puts "\n#{@terminal_message}"
      end

    end

    ##
    # A progress reporter that prints out messages about the current progress.

    class VerboseProgressReporter
      include DefaultUserInteraction

      attr_reader :count

      def initialize(out_stream, size, initial_message,
                     terminal_message = 'complete')
        @out = out_stream
        @total = size
        @count = 0
        @terminal_message = terminal_message

        @out.puts initial_message
      end

      ##
      # Prints out the position relative to the total and the +message+.

      def updated(message)
        @count += 1
        @out.puts "#{@count}/#{@total}: #{message}"
      end

      ##
      # Prints out the terminal message.

      def done
        @out.puts @terminal_message
      end
    end
  end

  ##
  # Subclass of StreamUI that instantiates the user interaction using STDIN,
  # STDOUT, and STDERR.

  class ConsoleUI < StreamUI
    def initialize
      super(STDIN, STDOUT, STDERR)
    end
  end

  ##
  # SilentUI is a UI choice that is absolutely silent.

  class SilentUI
    def method_missing(sym, *args, &block)
      self
    end
  end

end

