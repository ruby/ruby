# frozen_string_literal: true

require 'optparse'

module Lrama
  # Handle option parsing for the command line interface.
  class OptionParser
    def initialize
      @options = Options.new
      @trace = []
      @report = []
    end

    def parse(argv)
      parse_by_option_parser(argv)

      @options.trace_opts = validate_trace(@trace)
      @options.report_opts = validate_report(@report)
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
        o.on('-D', '--define=NAME[=VALUE]', Array, "similar to '%define NAME VALUE'") {|v| @options.define = v }
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
        o.on('-v', '--verbose', "same as '--report=state'") {|_v| @report << 'states' }
        o.separator ''
        o.separator 'Diagnostics:'
        o.on('-W', '--warnings', 'report the warnings') {|v| @options.diagnostic = true }
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

    ALIASED_REPORTS = { cex: :counterexamples }.freeze
    VALID_REPORTS = %i[states itemsets lookaheads solved counterexamples rules terms verbose].freeze

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

    def aliased_report_option(opt)
      (ALIASED_REPORTS[opt.to_sym] || opt).to_sym
    end

    VALID_TRACES = %w[
      locations scan parse automaton bitsets closure
      grammar rules only-explicit-rules actions resource
      sets muscles tools m4-early m4 skeleton time ielr cex
    ].freeze
    NOT_SUPPORTED_TRACES = %w[
      locations scan parse bitsets grammar resource
      sets muscles tools m4-early m4 skeleton ielr cex
    ].freeze
    SUPPORTED_TRACES = VALID_TRACES - NOT_SUPPORTED_TRACES

    def validate_trace(trace)
      h = {}
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
          raise "Invalid trace option \"#{t}\"."
        end
      end

      return h
    end
  end
end
