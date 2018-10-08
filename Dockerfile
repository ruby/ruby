FROM junaruga/ruby-docker:test

ARG TEST_USER=ruby
ARG WORK_DIR=/home/${TEST_USER}/code

# Create test user to pass the test.
RUN useradd "${TEST_USER}"
WORKDIR "${WORK_DIR}"
COPY . .
RUN chown -R "${TEST_USER}:${TEST_USER}" "${WORK_DIR}"
# Enable sudo without password for convenience.
RUN echo "${TEST_USER} ALL = NOPASSWD: ALL" >> /etc/sudoers

USER "${TEST_USER}"
