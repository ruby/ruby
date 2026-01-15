# frozen_string_literal: true

module ParserSupport
  module_function

  # Determines whether or not Prism is being used in the current process. This
  # would have been determined by `--parser=prism` on either the command line or
  # from within various environment variables.
  def prism_enabled?
    RubyVM::InstructionSequence.compile("").to_a[4][:parser] == :prism
  end

  # Determines whether or not Prism would be used by a subprocess. This is
  # necessary because some tests run in subprocesses, and we need to know if we
  # expect Prism to be used by those tests. This happens if Prism is configured
  # as the default parser.
  def prism_enabled_in_subprocess?
    EnvUtil.invoke_ruby(["-v"], "", true, false)[0].include?("+PRISM")
  end
end
