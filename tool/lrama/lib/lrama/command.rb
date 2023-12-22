module Lrama
  class Command
    def run(argv)
      options = OptionParser.new.parse(argv)

      Report::Duration.enable if options.trace_opts[:time]

      warning = Lrama::Warning.new
      text = options.y.read
      options.y.close if options.y != STDIN
      grammar = Lrama::Parser.new(text, options.grammar_file, options.debug).parse
      states = Lrama::States.new(grammar, warning, trace_state: (options.trace_opts[:automaton] || options.trace_opts[:closure]))
      states.compute
      context = Lrama::Context.new(states)

      if options.report_file
        reporter = Lrama::StatesReporter.new(states)
        File.open(options.report_file, "w+") do |f|
          reporter.report(f, **options.report_opts)
        end
      end

      if options.trace_opts && options.trace_opts[:rules]
        puts "Grammar rules:"
        puts grammar.rules
      end

      File.open(options.outfile, "w+") do |f|
        Lrama::Output.new(
          out: f,
          output_file_path: options.outfile,
          template_name: options.skeleton,
          grammar_file_path: options.grammar_file,
          header_file_path: options.header_file,
          context: context,
          grammar: grammar,
          error_recovery: options.error_recovery,
        ).render
      end

      if warning.has_error?
        exit 1
      end
    end
  end
end
