#
# YAML::Syck module
# .. glues syck and yaml.rb together ..
#
require 'syck'
require 'yaml/basenode'
require 'yaml/baseemitter'

module YAML
    module Syck

        #
        # Mixin BaseNode functionality
        #
        class Node
            include YAML::BaseNode
        end

        #
        # Mixin BaseEmitter functionality
        #
        class Emitter
            include YAML::BaseEmitter
        end

    end
end
