# frozen_string_literal: true
require_relative '../rubygems'
require_relative 'user_interaction'

##
# A post-install hook that displays "Successfully installed
# some_gem-1.0 as a default gem"

Gem.post_install do |installer|
  ui = Gem::DefaultUserInteraction.ui
  ui.say "Successfully installed #{installer.spec.full_name} as a default gem"
end
