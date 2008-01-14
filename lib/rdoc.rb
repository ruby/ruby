##
# :include: rdoc/README

module RDoc

  ##
  # Exception thrown by any rdoc error.

  class Error < RuntimeError; end

  RDocError = Error # :nodoc:

  ##
  # RDoc version you are using

  VERSION = "2.0.0"

  ##
  # Name of the dotfile that contains the description of files to be processed
  # in the current directory

  DOT_DOC_FILENAME = ".document"

  GENERAL_MODIFIERS = %w[nodoc].freeze

  CLASS_MODIFIERS = GENERAL_MODIFIERS

  ATTR_MODIFIERS  = GENERAL_MODIFIERS

  CONSTANT_MODIFIERS = GENERAL_MODIFIERS

  METHOD_MODIFIERS = GENERAL_MODIFIERS +
    %w[arg args yield yields notnew not-new not_new doc]

end

