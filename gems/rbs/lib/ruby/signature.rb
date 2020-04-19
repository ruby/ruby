require "ruby/signature/version"

require "set"
require "json"
require "pathname"
require "pp"
require "ripper"
require "logger"
require "tsort"

require "ruby/signature/errors"
require "ruby/signature/buffer"
require "ruby/signature/location"
require "ruby/signature/namespace"
require "ruby/signature/type_name"
require "ruby/signature/types"
require "ruby/signature/method_type"
require "ruby/signature/ast/declarations"
require "ruby/signature/ast/members"
require "ruby/signature/ast/annotation"
require "ruby/signature/environment"
require "ruby/signature/environment_loader"
require "ruby/signature/builtin_names"
require "ruby/signature/definition"
require "ruby/signature/definition_builder"
require "ruby/signature/variance_calculator"
require "ruby/signature/substitution"
require "ruby/signature/constant"
require "ruby/signature/constant_table"
require "ruby/signature/ast/comment"
require "ruby/signature/writer"
require "ruby/signature/prototype/rbi"
require "ruby/signature/prototype/rb"
require "ruby/signature/prototype/runtime"
require "ruby/signature/environment_walker"
require "ruby/signature/vendorer"

begin
  require "ruby/signature/parser"
rescue LoadError
  STDERR.puts "Missing parser Ruby code? Running `rake parser` may solve the issue"
  raise
end

module Ruby::Signature
  class <<self
    attr_reader :logger_level
    attr_reader :logger_output

    def logger
      @logger ||= Logger.new(logger_output || STDERR, level: logger_level || "warn", progname: "ruby-signature")
    end

    def logger_output=(val)
      @logger_output = val
      @logger = nil
    end

    def logger_level=(level)
      @logger_level = level
      @logger = nil
    end
  end
end
