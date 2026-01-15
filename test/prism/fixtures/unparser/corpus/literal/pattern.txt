case foo
in A[1, 2, *a, 3] then
  true
in [1, 2, ] then
  y
in A(x:) then
  true
in {**a} then
  true
in {} if true then
  true
in [x, y, *] then
  true
in {a: 1, aa: 2} then
  true
in {} then
  true
in {**nil} then
  true
in {"a": 1} then
  true
in 1 | 2 then
  true
in 1 => a then
  true
in ^x then
  true
in 1
in 2 then
  true
else
  true
end
case foo
in A[1, 2, *a, 3]
end
case foo
in A
else
end
1 in [a]
