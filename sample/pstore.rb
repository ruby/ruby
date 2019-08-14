require 'pstore'

db = PStore.new("/tmp/foo")
db.transaction do
  p db.roots
  ary = db["root"] = [1,2,3,4]
  ary[1] = [1,1.5]
end

1000.times do
  db.transaction do
    db["root"][0] += 1
    p db["root"][0]
  end
end

db.transaction(true) do
  p db["root"]
end
