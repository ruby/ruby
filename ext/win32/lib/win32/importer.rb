# frozen_string_literal: false
require 'fiddle/import'

module Win32
end

Win32.module_eval do
  Importer = Fiddle::Importer
end
