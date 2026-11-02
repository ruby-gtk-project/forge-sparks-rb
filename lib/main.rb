# frozen_string_literal: true

require 'adwaita'

require_relative 'util'
require_relative 'settings'
require_relative 'style'
require_relative 'forge'
require_relative 'forges'
require_relative 'notification'
require_relative 'notifications_list'
require_relative 'account'
require_relative 'accounts_manager'
require_relative 'notification_row'
require_relative 'shortcuts_dialog'
require_relative 'account_dialog'
require_relative 'accounts_dialog'
require_relative 'preferences_dialog'
require_relative 'window'
require_relative 'application'

# Main is the entry point.
#
# Ported from upstream's src/main.js and src/com.mardojai.ForgeSparks, the
# launcher script meson installs: both exist only to set the application name,
# teach Gio about the async methods the app awaits, and hand the argument
# vector to the application.
#
# Nothing here has to promisify anything — Util.defer is this port's answer to
# that — so what is left is the application name, the command line flags, and
# the one expression that runs the app.
#
module Main
  # The flags the application registers, documented here because upstream
  # declares them in main.js's Application constructor and this is the file
  # that takes the argument vector.
  #
  # --version, -v  Print version information and exit
  # --hidden       Start hidden
  OPTIONS = {
    '--version' => 'Print version information and exit',
    '--hidden'  => 'Start hidden',
  }.freeze

  module_function

  # Runs the application.
  #
  # @param argv [Array<String>] the argument vector, flags included
  # @return [Integer] the exit code
  def run(argv = [])
    GLib.application_name = Util::APP_NAME
    Application.new.build.run([$PROGRAM_NAME, *argv])
  end
end
