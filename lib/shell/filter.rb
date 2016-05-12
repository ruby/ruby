# frozen_string_literal: false
#
#   shell/filter.rb -
#       $Release Version: 0.7 $
#       $Revision$
#       by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

class Shell #:nodoc:
  # Any result of command execution is a Filter.
  #
  # This class includes Enumerable, therefore a Filter object can use all
  # Enumerable
  # facilities.
  #
  class Filter
    include Enumerable

    def initialize(sh)
      @shell = sh         # parent shell
      @input = nil        # input filter
    end

    attr_reader :input

    def input=(filter)
      @input = filter
    end

    # call-seq:
    #   each(record_separator=nil) { block }
    #
    # Iterates a block for each line.
    def each(rs = nil)
      rs = @shell.record_separator unless rs
      if @input
        @input.each(rs){|l| yield l}
      end
    end

    # call-seq:
    #   < source
    #
    # Inputs from +source+, which is either a string of a file name or an IO
    # object.
    def < (src)
      case src
      when String
        cat = Cat.new(@shell, src)
        cat | self
      when IO
        self.input = src
        self
      else
        Shell.Fail Error::CantApplyMethod, "<", to.class
      end
    end

    # call-seq:
    #   > source
    #
    # Outputs from +source+, which is either a string of a file name or an IO
    # object.
    def > (to)
      case to
      when String
        dst = @shell.open(to, "w")
        begin
          each(){|l| dst << l}
        ensure
          dst.close
        end
      when IO
        each(){|l| to << l}
      else
        Shell.Fail Error::CantApplyMethod, ">", to.class
      end
      self
    end

    # call-seq:
    #   >> source
    #
    # Appends the output to +source+, which is either a string of a file name
    # or an IO object.
    def >> (to)
      begin
        Shell.cd(@shell.pwd).append(to, self)
      rescue CantApplyMethod
        Shell.Fail Error::CantApplyMethod, ">>", to.class
      end
    end

    # call-seq:
    #   | filter
    #
    # Processes a pipeline.
    def | (filter)
      filter.input = self
      if active?
        @shell.process_controller.start_job filter
      end
      filter
    end

    # call-seq:
    #   filter1 + filter2
    #
    # Outputs +filter1+, and then +filter2+ using Join.new
    def + (filter)
      Join.new(@shell, self, filter)
    end

    def to_a
      ary = []
      each(){|l| ary.push l}
      ary
    end

    def to_s
      str = ""
      each(){|l| str.concat l}
      str
    end

    def inspect
      if @shell.debug.kind_of?(Integer) && @shell.debug > 2
        super
      else
        to_s
      end
    end
  end
end
