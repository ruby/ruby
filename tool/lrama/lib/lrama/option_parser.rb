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

      if !@options.grammar_file
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
        o.on('-t', 'reserved, do nothing') { }
        o.on('--debug', 'display debugging outputs of internal parser') {|v| @options.debug = true }
        o.separator ''
        o.separator 'Output:'
        o.on('-H', '--header=[FILE]', 'also produce a header file named FILE') {|v| @options.header = true; @options.header_file = v }
        o.on('-d', 'also produce a header file') { @options.header = true }
        o.on('-r', '--report=THINGS', Array, 'also produce details on the automaton') {|v| @report = v }
        o.on('--report-file=FILE', 'also produce details on the automaton output to a file named FILE') {|v| @options.report_file = v }
        o.on('-o', '--output=FILE', 'leave output to FILE') {|v| @options.outfile = v }
        o.on('--trace=THINGS', Array, 'also output trace logs at runtime') {|v| @trace = v }
        o.on('-v', 'reserved, do nothing') { }
        o.separator ''
        o.separator 'Error Recovery:'
        o.on('-e', 'enable error recovery') {|v| @options.error_recovery = true }
        o.separator ''
        o.separator 'Other options:'
        o.on('-V', '--version', "output version information and exit") {|v| puts "lrama #{Lrama::VERSION}"; exit 0 }
        o.on('-h', '--help', "display this help and exit") {|v| puts o; exit 0 }
        o.separator ''
        o.parse!(argv)
      end
    end

    def validate_report(report)
      bison_list = %w[states itemsets lookaheads solved counterexamples cex all none]
      others = %w[verbose]
      list = bison_list + others
      not_supported = %w[cex none]
      h = { grammar: true }

      report.each do |r|
        if list.include?(r) && !not_supported.include?(r)
          h[r.to_sym] = true
        else
          raise "Invalid report option \"#{r}\"."
        end
      end

      if h[:all]
        (bison_list - not_supported).each do |r|
          h[r.to_sym] = true
        end

        h.delete(:all)
      end

      return h
    end

    def validate_trace(trace)
      list = %w[
        none locations scan parse automaton bitsets
        closure grammar rules resource sets muscles tools
        m4-early m4 skeleton time ielr cex all
      ]
      h = {}

      trace.each do |t|
        if list.include?(t)
          h[t.to_sym] = true
        else
          raise "Invalid trace option \"#{t}\"."
        end
      end

      return h
    end
  end
end
