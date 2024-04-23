# frozen_string_literal: true

describe Sbmt::Outbox::Api::ApplicationRecord do
  let(:model) do
    Class.new(described_class) do
      attribute :id, :integer
    end
  end

  describe ".find" do
    context "when record exists" do
      let!(:record) { model.new(id: 14).tap(&:save) }

      it { expect(model.find(14)).to eq record }
    end

    context "when no record" do
      it { expect(model.find(14)).to be_nil }
    end
  end

  describe ".find_or_initialize" do
    context "when record exists" do
      let!(:record) { model.new(id: 14).tap(&:save) }

      it { expect(model.find_or_initialize(14, id: 14)).to eq record }
    end

    context "when no record" do
      it { expect(model.find_or_initialize(14, id: 14)).to have_attributes(id: 14) }
    end
  end

  describe ".delete" do
    context "when record exists" do
      let!(:record) { model.new(id: 14).tap(&:save) }

      before { model.delete(14) }

      it { expect(model.find(14)).to be_nil }
    end

    context "when no record" do
      it { expect(model.delete(14)).to be_zero }
    end
  end
end
