# frozen_string_literal: true

require 'spec_helper'

# Exercises Util.relative_date, the port of upstream's relativeDate(): the
# thresholds, the rounding and the two date-format fallbacks in src/util.js.
# Every case below was checked against the real method (not written from the
# formula alone) before being committed.
RSpec.describe Util do
  describe '.relative_date' do
    let(:now) { Time.utc(2026, 6, 15, 12, 0, 0) }

    it 'returns "now" for less than half a minute ago' do
      expect(Util.relative_date(now - 29, now: now)).to eq('now')
    end

    it 'returns singular minutes' do
      expect(Util.relative_date(now - 60, now: now)).to eq('1 minute ago')
    end

    it 'returns plural minutes' do
      expect(Util.relative_date(now - 300, now: now)).to eq('5 minutes ago')
    end

    it 'returns singular hours' do
      expect(Util.relative_date(now - 3600, now: now)).to eq('1 hour ago')
    end

    it 'returns plural hours' do
      expect(Util.relative_date(now - 10_800, now: now)).to eq('3 hours ago')
    end

    it 'returns "yesterday" for exactly one day ago' do
      expect(Util.relative_date(now - 86_400, now: now)).to eq('yesterday')
    end

    it 'returns plural days' do
      expect(Util.relative_date(now - 259_200, now: now)).to eq('3 days ago')
    end

    it 'returns plural weeks' do
      expect(Util.relative_date(now - 1_209_600, now: now)).to eq('2 weeks ago')
    end

    it 'falls back to a short date within the same year' do
      expect(Util.relative_date(Time.utc(2026, 1, 1), now: now)).to eq('on Jan 01')
    end

    it 'falls back to a full date across years' do
      expect(Util.relative_date(Time.utc(2024, 1, 1), now: now)).to eq('on 01 Jan, 2024')
    end

    it 'warns and returns "now" for a date in the future' do
      expect(Util).to receive(:warn).with('Date is in the future!')
      expect(Util.relative_date(now + 60, now: now)).to eq('now')
    end
  end
end
