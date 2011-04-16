struct tmx {
    VALUE year;
    int yday;
    int mon;
    int mday;
    int hour;
    int min;
    int sec;
    int wday;
    VALUE offset;
    const char *zone;
    VALUE timev;
};

/*
Local variables:
c-file-style: "ruby"
End:
*/
