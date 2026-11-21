# frozen_string_literal: true

# An in-memory Gem::CredentialStore backend for specs that exercise
# credential-store-enabled code paths without touching a real OS credential store.
class FakeCredentialBackend
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
