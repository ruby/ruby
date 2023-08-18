p <<~"E"
    x
  #{"  y"}
E

p <<~"E"
    x
  #{foo}
E

p <<~E
	x
        y
E

p <<~E
	x
    y
E

p <<~E
    	x
        y
E

p <<~E
        	x
	y
E

p <<~E
    x
  \	y
E

p <<~E
    x
  \  y
E

p <<~E
  E

p <<~E
  x

y
E

p <<~E
  x
    
  y
E

p <<~E
  x
    y
E

p <<~E
  x
E

p <<~E
  ð
E

p <<~E
E

p <<~`E`
    x
  #{foo}
E
