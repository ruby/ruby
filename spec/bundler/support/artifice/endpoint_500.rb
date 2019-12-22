# frozen_string_literal: true

require_relative "../path"
include Spec::Path

$LOAD_PATH.unshift(*Dir[Spec::Path.base_system_gems.join("gems/{artifice,mustermann,rack,tilt,sinatra}-*/lib")].map(&:to_s))

require "artifice"
require "sinatra/base"

Artifice.deactivate

class Endpoint500 < Sinatra::Base
  before do
    halt 500
  end
end

Artifice.activate_with(Endpoint500)
