#include <stdio.h>
#include <string.h>

static char internal_string[] = "internal_string";
long internal_long_value = 100;

struct test_struct {
  char c;
  long l;
};

union test_union {
  char c;
  int  i;
  long l;
  void *p;
};

struct test_data {
  char name[1024];
  struct test_data *next;
};

long
test_get_long_value()
{
  return internal_long_value;
};

void
test_set_long_value(long l)
{
  internal_long_value = l;
};

void
test_fill_test_struct(struct test_struct *ptr, char c, long l)
{
  ptr->c = c;
  ptr->l = l;
};

void
test_fill_test_union(union test_union *ptr, long l)
{
  ptr->l = l;
};

struct test_struct *
test_alloc_test_struct(char c, long l)
{
  struct test_struct *data;

  data = (struct test_struct *)malloc(sizeof(struct test_struct));
  data->c = c;
  data->l = l;

  return data;
};

int
test_c2i(char c)
{
  return (int)c;
};

char
test_i2c(int i)
{
  return (char)i;
};

long
test_lcc(char c1, char c2)
{
  return (long)(c1 + c2);
};

double
test_f2d(float f)
{
  double d;
  d = f;
  return d;
};

float
test_d2f(double d)
{
  float f;
  f = d;
  return f;
};

int
test_strlen(const char *str)
{
  return strlen(str);
};

int
test_isucc(int i)
{
  return (i+1);
};

long
test_lsucc(long l)
{
  return (l+1);
};

void
test_succ(long *l)
{
  (*l)++;
};

char *
test_strcat(char *str1, const char *str2)
{
  return strcat(str1, str2);
};

int
test_arylen(char *ary[])
{
  int i;
  for( i=0; ary[i]; i++ ){};
  return i;
};

void
test_append(char *ary[], int len, char *astr)
{
  int i;
  int size1,size2;
  char *str;

  size2 = strlen(astr);

  for( i=0; i <= len - 1; i++ ){
    size1 = strlen(ary[i]);
    str = (char*)malloc(size1 + size2 + 1);
    strcpy(str, ary[i]);
    strcat(str, astr);
    ary[i] = str;
  };
};

void
test_init(int *argc, char **argv[])
{
  int i;
  printf("test_init(0x%x,0x%x)\n",argc,argv);
  printf("\t*(0x%x) => %d\n",argc,*argc);
  for( i=0; i < (*argc); i++ ){
    printf("\t(*(0x%x)[%d]) => %s\n", argv, i, (*argv)[i]);
  };
};

FILE *
test_open(const char *filename, const char *mode)
{
  FILE *file;
  file = fopen(filename,mode);
  printf("test_open(%s,%s):0x%x\n",filename,mode,file);
  return file;
};

void
test_close(FILE *file)
{
  printf("test_close(0x%x)\n",file);
  fclose(file);
};

char *
test_gets(char *s, int size, FILE *f)
{
  return fgets(s,size,f);
};

typedef int callback1_t(int, char *);

int
test_callback1(int err, const char *msg)
{
  printf("internal callback function (err = %d, msg = '%s')\n",
	 err, msg ? msg : "(null)");
  return 1;
};

int
test_call_func1(callback1_t *func)
{
  if( func ){
    return (*func)(0, "this is test_call_func1.");
  }
  else{
    printf("test_call_func1(func = 0)\n");
    return -1;
  }
};

struct test_data *
test_data_init()
{
  struct test_data *data;

  data = (struct test_data *)malloc(sizeof(struct test_data));
  data->next = NULL;
  memset(data->name, 0, 1024);

  return data;
};

void
test_data_add(struct test_data *list, const char *name)
{
  struct test_data *data;

  data = (struct test_data *)malloc(sizeof(struct test_data));
  strcpy(data->name, name);
  data->next = list->next;
  list->next = data;
};

void
test_data_print(struct test_data *list)
{
  struct test_data *data;

  for( data = list->next; data; data = data->next ){
    printf("name = %s\n", data->name);
  };
};

struct data *
test_data_aref(struct test_data *list, int i)
{
  struct test_data *data;
  int j;

  for( data = list->next, j=0; data; data = data->next, j++ ){
    if( i == j ){
      return data;
    };
  };
  return NULL;
};
