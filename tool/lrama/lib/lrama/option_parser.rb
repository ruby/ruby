# rbs_inline: enabled
# frozen_string_literal: true

require 'optparse'

module Lrama
  # Handle option parsing for the command line interface.
  class OptionParser
    # @rbs!
    #   @options: Lrama::Options
    #   @trace: Array[String]
    #   @report: Array[String]
    #   @profile: Array[String]

    # @rbs (Array[String]) -> Lrama::Options
    def self.parse(argv)
      new.parse(argv)
    end

    # @rbs () -> void
    def initialize
      @options = Options.new
      @trace = []
      @report = []
      @profile = []
    end

    # @rbs (Array[String]) -> Lrama::Options
    def parse(argv)
      parse_by_option_parser(argv)

      @options.trace_opts = validate_trace(@trace)
      @options.report_opts = validate_report(@report)
      @options.profile_opts = validate_profile(@profile)
      @options.grammar_file = argv.shift

      unless @options.grammar_file
        abort "File should be specified\n"
      end

      if @options.grammar_file == '-'
        @options.grammar_file = argv.shift or abort "File name for STDIN should be specified\n"
      else
        @options.y = File.open(@options.grammar_file, 'r')
      end

      if !@report.empty? && @options.report_file.nil? && @options.grammar_file
        @options.report_file = File.dirname(@options.grammar_file) + "/" + File.basename(@options.grammar_file, ".*") + ".output"
      end

      if !@options.header_file && @options.header
        case
        when @options.outfile
          @options.header_file = File.dirname(@options.outfile) + "/" + File.basename(@options.outfile, ".*") + ".h"
        when @options.grammar_file
          @options.header_file = File.dirname(@options.grammar_file) + "/" + File.basename(@options.grammar_file, ".*") + ".h"
        end
      end

      @options
    end

    private

    # @rbs (Array[String]) -> void
    def parse_by_option_parser(argv)
      ::OptionParser.new do |o|
        o.banner = <<~BANNER
          Lrama is LALR (1) parser generator written by Ruby.

          Usage: lrama [options] FILE
        BANNER
        o.separator ''
        o.separator 'STDIN mode:'
        o.separator 'lrama [options] - FILE               read grammar from STDIN'
        o.separator ''
        o.separator 'Tuning the Parser:'
        o.on('-S', '--skeleton=FILE', 'specify the skeleton to use') {|v| @options.skeleton = v }
        o.on('-t', '--debug', 'display debugging outputs of internal parser') {|v| @options.debug = true }
        o.separator "                                     same as '-Dparse.trace'"
        o.on('--locations', 'enable location support') {|v| @options.locations = true }
        o.on('-D', '--define=NAME[=VALUE]', Array, "similar to '%define NAME VALUE'") do |v|
          @options.define = v.each_with_object({}) do |item, hash| # steep:ignore UnannotatedEmptyCollection
            key, value = item.split('=', 2)
            hash[key] = value
          end
        end
        o.separator ''
        o.separator 'Output:'
        o.on('-H', '--header=[FILE]', 'also produce a header file named FILE') {|v| @options.header = true; @options.header_file = v }
        o.on('-d', 'also produce a header file') { @options.header = true }
        o.on('-r', '--report=REPORTS', Array, 'also produce details on the automaton') {|v| @report = v }
        o.on_tail ''
        o.on_tail 'REPORTS is a list of comma-separated words that can include:'
        o.on_tail '    states                           describe the states'
        o.on_tail '    itemsets                         complete the core item sets with their closure'
        o.on_tail '    lookaheads                       explicitly associate lookahead tokens to items'
        o.on_tail '    solved                           describe shift/reduce conflicts solving'
        o.on_tail '    counterexamples, cex             generate conflict counterexamples'
        o.on_tail '    rules                            list unused rules'
        o.on_tail '    terms                            list unused terminals'
        o.on_tail '    verbose                          report detailed internal state and analysis results'
        o.on_tail '    all                              include all the above reports'
        o.on_tail '    none                             disable all reports'
        o.on('--report-file=FILE', 'also produce details on the automaton output to a file named FILE') {|v| @options.report_file = v }
        o.on('-o', '--output=FILE', 'leave output to FILE') {|v| @options.outfile = v }
        o.on('--trace=TRACES', Array, 'also output trace logs at runtime') {|v| @trace = v }
        o.on_tail ''
        o.on_tail 'TRACES is a list of comma-separated words that can include:'
        o.on_tail '    automaton                        display states'
        o.on_tail '    closure                          display states'
        o.on_tail '    rules                            display grammar rules'
        o.on_tail '    only-explicit-rules              display only explicit grammar rules'
        o.on_tail '    actions                          display grammar rules with actions'
        o.on_tail '    time                             display generation time'
        o.on_tail '    all                              include all the above traces'
        o.on_tail '    none                             disable all traces'
        o.on('--diagram=[FILE]', 'generate a diagram of the rules') do |v|
          @options.diagram = true
          @options.diagram_file = v if v
        end
        o.on('--profile=PROFILES', Array, 'profiles parser generation parts') {|v| @profile = v }
        o.on_tail ''
        o.on_tail 'PROFILES is a list of comma-separated words that can include:'
        o.on_tail '    call-stack                       use sampling call-stack profiler (stackprof gem)'
        o.on_tail '    memory                           use memory profiler (memory_profiler gem)'
        o.on('-v', '--verbose', "same as '--report=state'") {|_v| @report << 'states' }
        o.separator ''
        o.separator 'Diagnostics:'
        o.on('-W', '--warnings', 'report the warnings') {|v| @options.warnings = true }
        o.separator ''
        o.separator 'Error Recovery:'
        o.on('-e', 'enable error recovery') {|v| @options.error_recovery = true }
        o.separator ''
        o.separator 'Other options:'
        o.on('-V', '--version', "output version information and exit") {|v| puts "lrama #{Lrama::VERSION}"; exit 0 }
        o.on('-h', '--help', "display this help and exit") {|v| puts o; exit 0 }
        o.on_tail
        o.parse!(argv)
      end
    end

    ALIASED_REPORTS = { cex: :counterexamples }.freeze #: Hash[Symbol, Symbol]
    VALID_REPORTS = %i[states itemsets lookaheads solved counterexamples rules terms verbose].freeze #: Array[Symbol]

    # @rbs (Array[String]) -> Hash[Symbol, bool]
    def validate_report(report)
      h = { grammar: true }
      return h if report.empty?
      return {} if report == ['none']
      if report == ['all']
        VALID_REPORTS.each { |r| h[r] = true }
        return h
      end

      report.each do |r|
        aliased = aliased_report_option(r)
        if VALID_REPORTS.include?(aliased)
          h[aliased] = true
        else
          raise "Invalid report option \"#{r}\"."
        end
      end

      return h
    end

    # @rbs (String) -> Symbol
    def aliased_report_option(opt)
      (ALIASED_REPORTS[opt.to_sym] || opt).to_sym
    end

    VALID_TRACES = %w[
      locations scan parse automaton bitsets closure
      grammar rules only-explicit-rules actions resource
      sets muscles tools m4-early m4 skeleton time ielr cex
    ].freeze #: Array[String]
    NOT_SUPPORTED_TRACES = %w[
      locations scan parse bitsets grammar resource
      sets muscles tools m4-early m4 skeleton ielr cex
    ].freeze #: Array[String]
    SUPPORTED_TRACES = VALID_TRACES - NOT_SUPPORTED_TRACES #: Array[String]

    # @rbs (Array[String]) -> Hash[Symbol, bool]
    def validate_trace(trace)
      h = {} #: Hash[Symbol, bool]
      return h if trace.empty? || trace == ['none']
      all_traces = SUPPORTED_TRACES - %w[only-explicit-rules]
      if trace == ['all']
        all_traces.each { |t| h[t.gsub(/-/, '_').to_sym] = true }
        return h
      end

      trace.each do |t|
        if SUPPORTED_TRACES.include?(t)
          h[t.gsub(/-/, '_').to_sym] = true
        else
          raise "Invalid trace option \"#{t}\".\nValid options are [#{SUPPORTED_TRACES.join(", ")}]."
        end
      end

      return h
    end

    VALID_PROFILES = %w[call-stack memory].freeze #: Array[String]

    # @rbs (Array[String]) -> Hash[Symbol, bool]
    def validate_profile(profile)
      h = {} #: Hash[Symbol, bool]
      return h if profile.empty?

      profile.each do |t|
        if VALID_PROFILES.include?(t)
          h[t.gsub(/-/, '_').to_sym] = true
        else
          raise "Invalid profile option \"#{t}\".\nValid options are [#{VALID_PROFILES.join(", ")}]."
        end
      end

      return h
    end
  end
end
