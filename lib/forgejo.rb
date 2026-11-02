# frozen_string_literal: true

require_relative 'gitea'

# Forgejo is the Forgejo backend.
#
# Ported from upstream's src/forges/forgejo.js. Forgejo and Gitea have
# compatible APIs, so this only names the forge and its default instance and
# derives everything else. Upstream keeps them separate in case that changes;
# so does this.
#
class Forgejo < Gitea
  class << self
    def forge_name = 'forgejo'
    def pretty_name = 'Forgejo'
    def allow_instances? = true
    def default_url = 'codeberg.org'
  end
end
