# frozen_string_literal: true

##
# An in-memory Gem::CredentialStore backend for tests that need to exercise
# credential-store-enabled code paths without touching a real OS credential store.
# Inject it via <tt>Gem::CredentialStore.instance = Gem::CredentialStore.new(backend: Gem::FakeCredentialBackend.new)</tt>.

class Gem::FakeCredentialBackend
  def initialize
    @data = {}
  end

  def get(service, account)
    @data[[service, account]]
  end

  def set(service, account, secret)
    @data[[service, account]] = secret
    true
  end

  def delete(service, account)
    @data.delete([service, account])
    true
  end

  def list(service)
    @data.keys.select {|entry_service, _account| entry_service == service }.map(&:last)
  end

  def delete_all(service)
    @data.reject! {|(entry_service, _account), _secret| entry_service == service }
    true
  end
end
