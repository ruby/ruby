# frozen_string_literal: true

require_relative "../path"

$LOAD_PATH.unshift(*Dir[Spec::Path.base_system_gem_path.join("gems/{mustermann,rack,tilt,sinatra,ruby2_keywords}-*/lib")].map(&:to_s))

require "sinatra/base"

class Endpoint500 < Sinatra::Base
  before do
    halt 500
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(Endpoint500)
