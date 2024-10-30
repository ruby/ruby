ENV['GEM_HOME'] = gem_home = File.expand_path('.bundle')
ENV['GEM_PATH'] = [gem_home, File.expand_path('../../../.bundle', __FILE__)].uniq.join(File::PATH_SEPARATOR)
