#
# YAML::Syck module
# .. glues syck and yaml.rb together ..
#
require 'syck'
require 'yaml/basenode'

module YAML
    module Syck

        #
        # Mixin BaseNode functionality
        #
        class Node
            include YAML::BaseNode
        end

    end
end
