# frozen_string_literal: false
require 'psych/versions'
require 'psych.jar'

require 'jar-dependencies'
require_jar('org.yaml', 'snakeyaml', Psych::DEFAULT_SNAKEYAML_VERSION)
