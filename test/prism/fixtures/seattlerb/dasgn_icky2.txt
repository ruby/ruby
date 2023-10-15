a do
  v = nil
  begin
    yield
  rescue Exception => v
    break
  end
end
