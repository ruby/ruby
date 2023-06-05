# directory access
# list all files but .*/*~/*.o
Dir.foreach(".") do |file|
  unless file.start_with?('.') or file.end_with?('~', '.o')
    puts file
  end
end
