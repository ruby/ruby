#include <stdio.h>

class Person {
private:
  const char *name;
  int age;

public:
  Person(const char *name, int age);
  const char * get_name();
  int get_age();
  void set_age(int i);
};

Person::Person(const char *name, int age)
  : name(name), age(age)
{
  /* empty */
}

const char *
Person::get_name()
{
  return name;
}

int
Person::get_age(){
  return age;
}

void
Person::set_age(int i){
  age = i;
}
