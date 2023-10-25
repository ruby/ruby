# frozen_string_literal: true

require_relative "ruby-lex"

module IRB
  class SourceFinder
    Source = Struct.new(
      :file,       # @param [String] - file name
      :first_line, # @param [String] - first line
      :last_line,  # @param [String] - last line
      keyword_init: true,
    )
    private_constant :Source

    def initialize(irb_context)
      @irb_context = irb_context
    end

    def find_source(signature)
      context_binding = @irb_context.workspace.binding
      case signature
      when /\A[A-Z]\w*(::[A-Z]\w*)*\z/ # Const::Name
        eval(signature, context_binding) # trigger autoload
        base = context_binding.receiver.yield_self { |r| r.is_a?(Module) ? r : Object }
        file, line = base.const_source_location(signature)
      when /\A(?<owner>[A-Z]\w*(::[A-Z]\w*)*)#(?<method>[^ :.]+)\z/ # Class#method
        owner = eval(Regexp.last_match[:owner], context_binding)
        method = Regexp.last_match[:method]
        if owner.respond_to?(:instance_method)
          methods = owner.instance_methods + owner.private_instance_methods
          file, line = owner.instance_method(method).source_location if methods.include?(method.to_sym)
        end
      when /\A((?<receiver>.+)(\.|::))?(?<method>[^ :.]+)\z/ # method, receiver.method, receiver::method
        receiver = eval(Regexp.last_match[:receiver] || 'self', context_binding)
        method = Regexp.last_match[:method]
        file, line = receiver.method(method).source_location if receiver.respond_to?(method, true)
      end
      if file && line && File.exist?(file)
        Source.new(file: file, first_line: line, last_line: find_end(file, line))
      end
    end

    private

    def find_end(file, first_line)
      lex = RubyLex.new
      lines = File.read(file).lines[(first_line - 1)..-1]
      tokens = RubyLex.ripper_lex_without_warning(lines.join)
      prev_tokens = []

      # chunk with line number
      tokens.chunk { |tok| tok.pos[0] }.each do |lnum, chunk|
        code = lines[0..lnum].join
        prev_tokens.concat chunk
        continue = lex.should_continue?(prev_tokens)
        syntax = lex.check_code_syntax(code, local_variables: [])
        if !continue && syntax == :valid
          return first_line + lnum
        end
      end
      first_line
    end
  end
end
