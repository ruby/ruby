require 'optparse'

module Lrama
  class Command
    def run(argv)
      opt = OptionParser.new

      # opt.on('-h') {|v| p v }
      opt.on('-V', '--version') {|v| puts Lrama::VERSION ; exit 0 }

      # Tuning the Parser
      skeleton = "bison/yacc.c"

      opt.on('-S', '--skeleton=FILE') {|v| skeleton = v }
      opt.on('-t') {  } # Do nothing

      # Output Files:
      header = false
      header_file = nil
      report = []
      report_file = nil
      outfile = "y.tab.c"

      opt.on('-h', '--header=[FILE]') {|v| header = true; header_file = v }
      opt.on('-d') { header = true }
      opt.on('-r', '--report=THINGS') {|v| report = v.split(',') }
      opt.on('--report-file=FILE')    {|v| report_file = v }
      opt.on('-v') {  } # Do nothing
      opt.on('-o', '--output=FILE')   {|v| outfile = v }

      # Hidden
      trace = []
      opt.on('--trace=THINGS') {|v| trace = v.split(',') }

      # Error Recovery
      error_recovery = false
      opt.on('-e') {|v| error_recovery = true }

      opt.parse!(argv)

      trace_opts = validate_trace(trace)
      report_opts = validate_report(report)

      grammar_file = argv.shift

      if !report.empty? && report_file.nil? && grammar_file
        report_file = File.dirname(grammar_file) + "/" + File.basename(grammar_file, ".*") + ".output"
      end

      if !header_file && header
        case
        when outfile
          header_file = File.dirname(outfile) + "/" + File.basename(outfile, ".*") + ".h"
        when grammar_file
          header_file = File.dirname(grammar_file) + "/" + File.basename(grammar_file, ".*") + ".h"
        end
      end

      if !grammar_file
        abort "File should be specified\n"
      end

      Report::Duration.enable if trace_opts[:time]

      warning = Lrama::Warning.new
      if grammar_file == '-'
        grammar_file = argv.shift or abort "File name for STDIN should be specified\n"
        y = STDIN.read
      else
        y = File.read(grammar_file)
      end
      grammar = Lrama::Parser.new(y).parse
      states = Lrama::States.new(grammar, warning, trace_state: (trace_opts[:automaton] || trace_opts[:closure]))
      states.compute
      context = Lrama::Context.new(states)

      if report_file
        reporter = Lrama::StatesReporter.new(states)
        File.open(report_file, "w+") do |f|
          reporter.report(f, **report_opts)
        end
      end

      File.open(outfile, "w+") do |f|
        Lrama::Output.new(
          out: f,
          output_file_path: outfile,
          template_name: skeleton,
          grammar_file_path: grammar_file,
          header_file_path: header_file,
          context: context,
          grammar: grammar,
        ).render
      end

      if warning.has_error?
        exit 1
      end
    end

    private

    def validate_report(report)
      bison_list = %w[states itemsets lookaheads solved counterexamples cex all none]
      others = %w[verbose]
      list = bison_list + others
      not_supported = %w[counterexamples cex none]
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
        closure grammar resource sets muscles tools
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
