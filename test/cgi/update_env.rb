# frozen_string_literal: false
module UpdateEnv
  def update_env(environ)
    environ.each do |key, val|
      @environ[key] = ENV[key] unless @environ.key?(key)
      ENV[key] = val
    end
  end
end
