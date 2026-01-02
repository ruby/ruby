# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  # Command line options.
  class Options
    attr_accessor :skeleton #: String
    attr_accessor :locations #: bool
    attr_accessor :header #: bool
    attr_accessor :header_file #: String?
    attr_accessor :report_file #: String?
    attr_accessor :outfile #: String
    attr_accessor :error_recovery #: bool
    attr_accessor :grammar_file #: String
    attr_accessor :trace_opts #: Hash[Symbol, bool]?
    attr_accessor :report_opts #: Hash[Symbol, bool]?
    attr_accessor :warnings #: bool
    attr_accessor :y #: IO
    attr_accessor :debug #: bool
    attr_accessor :define #: Hash[String, String]
    attr_accessor :diagram #: bool
    attr_accessor :diagram_file #: String
    attr_accessor :profile_opts #: Hash[Symbol, bool]?

    # @rbs () -> void
    def initialize
      @skeleton = "bison/yacc.c"
      @locations = false
      @define = {}
      @header = false
      @header_file = nil
      @report_file = nil
      @outfile = "y.tab.c"
      @error_recovery = false
      @grammar_file = ''
      @trace_opts = nil
      @report_opts = nil
      @warnings = false
      @y = STDIN
      @debug = false
      @diagram = false
      @diagram_file = "diagram.html"
      @profile_opts = nil
    end
  end
end
