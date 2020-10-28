# frozen-string-literal: true

require_relative "../spell_checker"
require_relative "../tree_spell_checker"

module DidYouMean
  class RequirePathChecker
    attr_reader :path

    INITIAL_LOAD_PATH = $LOAD_PATH.dup.freeze
    ENV_SPECIFIC_EXT  = ".#{RbConfig::CONFIG["DLEXT"]}"

    private_constant :INITIAL_LOAD_PATH, :ENV_SPECIFIC_EXT

    def self.requireables
      @requireables ||= INITIAL_LOAD_PATH
                          .flat_map {|path| Dir.glob("**/???*{.rb,#{ENV_SPECIFIC_EXT}}", base: path) }
                          .map {|path| path.chomp!(".rb") || path.chomp!(ENV_SPECIFIC_EXT) }
    end

    def initialize(exception)
      @path = exception.path
    end

    def corrections
      @corrections ||= begin
                         threshold     = path.size * 2
                         dictionary    = self.class.requireables.reject {|str| str.size >= threshold }
                         spell_checker = path.include?("/") ? TreeSpellChecker : SpellChecker

                         spell_checker.new(dictionary: dictionary).correct(path).uniq
                       end
    end
  end
end
