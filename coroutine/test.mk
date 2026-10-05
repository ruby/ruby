COROUTINE_TEST_DIR = coroutine/test
COROUTINE_TEST = $(COROUTINE_TEST_DIR)/run$(EXEEXT)
COROUTINE_TEST_OBJS = \
		$(COROUTINE_TEST_DIR)/main.$(OBJEXT) \
		$(COROUTINE_TEST_DIR)/stack.$(OBJEXT) \
		$(COROUTINE_TEST_DIR)/test_initialize_destroy.$(OBJEXT) \
		$(COROUTINE_TEST_DIR)/test_pthread_resume.$(OBJEXT) \
		$(COROUTINE_TEST_DIR)/test_transfer_repeat.$(OBJEXT) \
		$(COROUTINE_TEST_DIR)/test_transfer_return.$(OBJEXT) \
		$(empty) # COROUTINE_TEST_OBJS

$(COROUTINE_TEST): $(COROUTINE_TEST_OBJS) $(COROUTINE_OBJ)
	$(ECHO) linking $@
	$(Q) $(COROUTINE_TEST_LINK)

# NMake defines $< only in inference rules.  Use $* to derive the source.
$(COROUTINE_TEST_OBJS): $(COROUTINE_TEST_DIR)/.time
	$(ECHO) compiling $(srcdir)/$*.c
	$(Q) $(CC) $(CFLAGS) $(XCFLAGS) $(CPPFLAGS) $(COUTFLAG)$@ -c $(CSRCFLAG)$(srcdir)/$*.c

$(COROUTINE_TEST_DIR)/.time:
	$(Q) $(MAKEDIRS) $(@D)
	@$(NULLCMD) > $@

test-coroutine: $(TEST_RUNNABLE:yes=do)-test-coroutine
test-coroutine-$(GITHUB_ACTIONS:true=prereq): build-ext
test-coroutine-prereq:
yes-test-coroutine: test-coroutine-prereq PHONY
	$(ACTIONS_GROUP)
do-test-coroutine: yes-test-coroutine $(DOT_WAIT) $(COROUTINE_TEST) PHONY
	$(Q)$(COROUTINE_TEST_RUN)
	$(ACTIONS_ENDGROUP)
no-test-coroutine: PHONY

clean-test-coroutine:
	$(Q)$(RM) $(COROUTINE_TEST) $(COROUTINE_TEST_DIR)/run.* $(COROUTINE_TEST_OBJS) $(COROUTINE_TEST_DIR)/.time
	$(Q)$(RMDIRS) $(COROUTINE_TEST_DIR) 2> $(NULL) || $(NULLCMD)

clean-local:: clean-test-coroutine
