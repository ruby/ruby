load File.dirname(__FILE__) + '/default.mspec'

class MSpecScript
  set :library, get(:stdlibs).to_a & get(:bundled_gems).to_a
  set :files, get(:library)
end
