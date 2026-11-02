# frozen_string_literal: true

require_relative 'forge'
require_relative 'forgejo'
require_relative 'gitea'
require_relative 'github'
require_relative 'gitlab'

# Forges is the registry of forge backends.
#
# Ported from upstream's src/forges/index.js: the map a saved account's forge
# name is looked up in, and the id split that takes an account id and a
# notification id back out of the id Forge#format_id built.
#
module Forges
  # Map of forge implementations, in the order the account dialog lists them.
  FORGES = {
    'forgejo' => Forgejo,
    'gitea'   => Gitea,
    'github'  => GitHub,
    'gitlab'  => GitLab,
  }.freeze

  # The length of the account uuid that #extract_id splits on.
  ID_LENGTH = 36

  module_function

  # The backend class for a forge name.
  def [](name) = FORGES[name.to_s]

  # Every backend class, in listing order.
  def all = FORGES.values

  # Extract the account and notification ids from an id Forge#format_id made.
  #
  # @return [Array(String, String)]
  def extract_id(id)
    [id.to_s.slice(0, ID_LENGTH).to_s, id.to_s.slice(ID_LENGTH + 1..).to_s]
  end
end
