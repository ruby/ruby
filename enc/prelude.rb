%w'enc/encdb enc/trans/transdb'.each do |init|
  begin
    require(init)
  rescue LoadError
  end
end
