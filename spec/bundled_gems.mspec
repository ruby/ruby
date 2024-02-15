load File.dirname(__FILE__) + '/default.mspec'

class MSpecScript
  gems = (get(:stdlibs).to_a & get(:bundled_gems).to_a).map{|gem| gem unless gem =~ /ftp/}.compact

  set :library, gems
  set :files, get(:library)
end
