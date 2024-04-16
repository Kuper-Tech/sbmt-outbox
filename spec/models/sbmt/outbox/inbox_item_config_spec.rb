# frozen_string_literal: true

describe Sbmt::Outbox::InboxItemConfig do
  let(:config) { InboxItem.config }

  describe "polling auto enabled by default" do
    it { expect(config.polling_enabled?).to be true }
  end

  context "when polling is disabled" do
    before { Sbmt::Outbox::Api::InboxItem.new(id: InboxItem.box_name, polling_enabled: false).save }

    it { expect(config.polling_enabled?).to be false }
  end

  context "when polling is auto disabled" do
    before { allow(config).to receive(:polling_auto_disabled?).and_return(true) }

    it { expect(config.polling_enabled?).to be false }

    context "when polling is enabled on the box" do
      before { Sbmt::Outbox::Api::InboxItem.new(id: InboxItem.box_name, polling_enabled: true).save }

      it { expect(config.polling_enabled?).to be true }
    end
  end
end
