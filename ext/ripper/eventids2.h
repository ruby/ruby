#ifndef RIPPER_EVENTIDS2
#define RIPPER_EVENTIDS2

void ripper_init_eventids2(void);
void ripper_init_eventids2_table(VALUE self);
ID ripper_token2eventid(enum yytokentype tok);

#endif /* RIPPER_EVENTIDS2 */
