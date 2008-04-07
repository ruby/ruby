%w'enc/init enc/trans/init'.each do |init|
  begin
    require(init)
  rescue LoadError
  end
end
