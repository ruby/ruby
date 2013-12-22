begin
  require 'fiddle/import'
  importer = Fiddle::Importer
rescue LoadError
  require 'dl/import'
  importer = DL::Importer
end

module Win32
end

Win32.module_eval do
  Importer = importer
end
