# frozen_string_literal: true

require 'gtk4'

require_relative 'notification'

# NotificationsList is the list model holding the notifications on screen.
#
# Ported from upstream's src/model/notificationsList.js, which implements
# Gio.ListModel over a private array and emits items-changed from #clear,
# #append and #removeByID.
#
# ruby-gnome cannot implement the Gio::ListModel interface from Ruby, so the
# model is a Gio::ListStore wrapped in this class rather than a subclass of
# one. The wrapper also keeps its own ordered Array, and every read goes
# through that Array instead of the store: removing an item from a
# Gio::ListStore drops the reference keeping it alive, and a Ruby wrapper GTK
# hands back afterwards can point at freed memory. The store still drives
# anything bound to the model; it is just not the source of truth.
#
class NotificationsList
  def initialize
    @notifications = []
    @list_store = Gio::ListStore.new(Notification)
    @listeners = []
  end

  attr_reader :list_store

  # Registers a block to run after every change, which is what upstream's
  # consumers connect to items-changed for.
  def on_items_changed(&listener) = @listeners << listener

  def n_items = @notifications.length

  # Every notification, newest first.
  #
  # Upstream sorts with a Gtk.SortListModel over a timestamp property
  # expression; the properties here are plain attributes, so the sort happens
  # in Ruby and the order is the one the window renders.
  def sorted = @notifications.sort_by { |notification| -notification.timestamp }

  def clear
    @notifications.clear
    @list_store.remove_all
    notify_items_changed
  end

  def append(notification)
    @notifications << notification
    @list_store.append(notification)
    notify_items_changed
  end

  def get_by_id(id) = @notifications.find { |notification| notification.id == id }

  def remove_by_id(id)
    @notifications.index { |notification| notification.id == id }.then do |index|
      if index
        @notifications.delete_at(index)
        @list_store.remove(index)
        notify_items_changed
      end
    end
  end

  private

    def notify_items_changed = @listeners.each(&:call)
end
