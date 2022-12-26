# directory access
# list all files but .*/*~/*.o
Dir.foreach(".") do |file|
  unless file.match(/\A\./, /~\z/, /\.o\z/)
    puts file
  end
end
