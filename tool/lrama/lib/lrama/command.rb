# frozen_string_literal: true

module Lrama
  class Command
    LRAMA_LIB = File.realpath(File.join(File.dirname(__FILE__)))
    STDLIB_FILE_PATH = File.join(LRAMA_LIB, 'grammar', 'stdlib.y')

    def initialize(argv)
      @logger = Lrama::Logger.new
      @options = OptionParser.parse(argv)
      @tracer = Tracer.new(STDERR, **@options.trace_opts)
      @reporter = Reporter.new(**@options.report_opts)
      @warnings = Warnings.new(@logger, @options.warnings)
    rescue => e
      abort format_error_message(e.message)
    end

    def run
      Lrama::Reporter::Profile::CallStack.report(@options.profile_opts[:call_stack]) do
        Lrama::Reporter::Profile::Memory.report(@options.profile_opts[:memory]) do
          execute_command_workflow
        end
      end
    end

    private

    def execute_command_workflow
      @tracer.enable_duration
      text = read_input
      grammar = build_grammar(text)
      states, context = compute_status(grammar)
      render_reports(states) if @options.report_file
      @tracer.trace(grammar)
      render_diagram(grammar)
      render_output(context, grammar)
      states.validate!(@logger)
      @warnings.warn(grammar, states)
    end

    def read_input
      text = @options.y.read
      @options.y.close unless @options.y == STDIN
      text
    end

    def build_grammar(text)
      grammar =
        Lrama::Parser.new(text, @options.grammar_file, @options.debug, @options.locations, @options.define).parse
      merge_stdlib(grammar)
      prepare_grammar(grammar)
      grammar
    rescue => e
      raise e if @options.debug
      abort format_error_message(e.message)
    end

    def format_error_message(message)
      return message unless Exception.to_tty?

      message.gsub(/.+/, "\e[1m\\&\e[m")
    end

    def merge_stdlib(grammar)
      return if grammar.no_stdlib

      stdlib_text = File.read(STDLIB_FILE_PATH)
      stdlib_grammar = Lrama::Parser.new(
        stdlib_text,
        STDLIB_FILE_PATH,
        @options.debug,
        @options.locations,
        @options.define,
      ).parse

      grammar.prepend_parameterized_rules(stdlib_grammar.parameterized_rules)
    end

    def prepare_grammar(grammar)
      grammar.prepare
      grammar.validate!
    end

    def compute_status(grammar)
      states = Lrama::States.new(grammar, @tracer)
      states.compute
      states.compute_ielr if grammar.ielr_defined?
      [states, Lrama::Context.new(states)]
    end

    def render_reports(states)
      File.open(@options.report_file, "w+") do |f|
        @reporter.report(f, states)
      end
    end

    def render_diagram(grammar)
      return unless @options.diagram

      File.open(@options.diagram_file, "w+") do |f|
        Lrama::Diagram.render(out: f, grammar: grammar)
      end
    end

    def render_output(context, grammar)
      File.open(@options.outfile, "w+") do |f|
        Lrama::Output.new(
          out: f,
          output_file_path: @options.outfile,
          template_name: @options.skeleton,
          grammar_file_path: @options.grammar_file,
          header_file_path: @options.header_file,
          context: context,
          grammar: grammar,
          error_recovery: @options.error_recovery,
        ).render
      end
    end
  end
end
