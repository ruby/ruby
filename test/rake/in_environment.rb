module InEnvironment
  private

  # Create an environment for a test. At the completion of the yielded
  # block, the environment is restored to its original conditions.
  def in_environment(settings)
    original_settings = set_env(settings)
    yield
  ensure
    set_env(original_settings) if original_settings
  end

  # Set the environment according to the settings hash.
  def set_env(settings)         # :nodoc:
    result = {}
    settings.each do |k, v|
      result[k] = ENV[k]
      if k == 'PWD'
        result[k] = Dir.pwd
        Dir.chdir(v)
      elsif v.nil?
        ENV.delete(k)
      else
        ENV[k] = v
      end
    end
    result
  end

end
