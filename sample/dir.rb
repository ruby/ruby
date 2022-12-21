# directory access
# list all files but .*/*~/*.o
Dir.open(".").each do |file|
  unless file.match(/\A\./, /~\z/, /\.o\z/)
    puts file
  end
end
