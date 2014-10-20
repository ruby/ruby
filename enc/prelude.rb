%w'enc/encdb.so enc/trans/transdb.so'.each do |init|
  begin
    require(init)
  rescue LoadError
  end
end

begin
  require 'unicode_normalize'
rescue LoadError
end
