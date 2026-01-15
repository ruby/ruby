# frozen_string_literal: true

require_relative "../path"

$LOAD_PATH.unshift(*Spec::Path.sinatra_dependency_paths)

require "sinatra/base"

class Endpoint500 < Sinatra::Base
  before do
    halt 500
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(Endpoint500)
