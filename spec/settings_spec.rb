# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

# Exercises Settings, the JSON-file stand-in for upstream's GSettings schema
# (data/com.mardojai.ForgeSparks.gschema.xml): the app-level keys, their
# defaults, persistence across instances, and the per-account relocated view
# AccountSettings provides through #account.
RSpec.describe Settings do
  around do |example|
    Dir.mktmpdir('forge-sparks-settings-spec') do |dir|
      @path = File.join(dir, 'settings.json')
      example.run
    end
  end

  subject(:settings) { described_class.new(path: @path) }

  describe 'defaults' do
    it 'matches upstream\'s schema defaults' do
      expect(settings['first-run']).to be(false)
      expect(settings['hide-on-close']).to be(false)
      expect(settings['autostart']).to be(false)
      expect(settings['autostart-hidden']).to be(false)
      expect(settings['window-size']).to eq([780, 480])
      expect(settings['accounts']).to eq([])
      expect(settings['notified']).to eq({})
    end

    it 'exposes the boolean keys through named predicate methods' do
      expect(settings.hide_on_close?).to be(false)
      expect(settings.autostart?).to be(false)
    end
  end

  describe '#[]=' do
    it 'writes through the named accessor too' do
      settings.hide_on_close = true
      expect(settings['hide-on-close']).to be(true)
      expect(settings.hide_on_close?).to be(true)
    end

    it 'persists across instances backed by the same file' do
      settings['autostart'] = true
      expect(described_class.new(path: @path)['autostart']).to be(true)
    end
  end

  describe '#account' do
    it 'defaults every account key from the account schema' do
      account = settings.account('42')
      expect(account.forge).to eq('github')
      expect(account.url).to eq('github.com')
      expect(account.username).to eq('')
      expect(account.user_id).to eq(0)
    end

    it 'writes an account key through the owning settings store' do
      settings.account('42').username = 'octocat'
      expect(settings.account_values('42')['username']).to eq('octocat')
    end

    it 'memoizes the view per account id' do
      expect(settings.account('42')).to be(settings.account('42'))
    end

    it 'persists account values across instances' do
      settings.account('42').user_id = 99
      reopened = described_class.new(path: @path)
      expect(reopened.account('42').user_id).to eq(99)
    end
  end

  describe '#forget_account' do
    it 'drops a stored account entirely' do
      settings.account('42').username = 'octocat'
      settings.forget_account('42')
      expect(settings.account_values('42')).to eq({})
    end
  end

  describe '#remember and #apply_to' do
    it 'round-trips the window size through a fake window' do
      window = Struct.new(:default_width, :default_height) do
        def set_default_size(width, height)
          self.default_width = width
          self.default_height = height
        end
      end.new(780, 480)

      settings.remember(window)
      expect(settings['window-size']).to eq([780, 480])

      settings['window-size'] = [900, 600]
      settings.apply_to(window)
      expect([window.default_width, window.default_height]).to eq([900, 600])
    end
  end
end
