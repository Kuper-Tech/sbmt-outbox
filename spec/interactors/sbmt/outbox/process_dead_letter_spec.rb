# frozen_string_literal: true

describe Sbmt::Outbox::ProcessDeadLetter do
  let!(:letter) { Fabricate(:dead_letter) }
  let(:letter_id) { letter.id }
  let(:result) { described_class.call(letter.class, letter_id) }

  context "when all params is valid" do
    let(:handler) do
      Class.new do
        extend Dry::Monads[:result]

        def self.call(_payload, _metadata)
          Success()
        end
      end
    end

    it "handles and destroys dead letter" do
      expect(Sbmt::Outbox.logger).to receive(:log_success)
      expect(Sbmt::Outbox.error_tracker).not_to receive(:error)

      expect { result }.to change(DeadLetter, :count).by(-1)
      expect(result).to be_success
    end

    it "calls handler with valid args" do
      expect(handler).to receive(:call).with(
        letter.payload,
        hash_including(sequence_id: kind_of(Integer), event_timestamp: kind_of(Time))
      ).and_call_original

      allow_any_instance_of(DeadLetter).to receive(:handler).and_return(handler)

      expect(result).to be_success
    end
  end

  context "when letter not found" do
    let(:letter_id) { 0 }

    it "returns fatal error" do
      expect(Sbmt::Outbox.logger).to receive(:log_failure)
      expect(Sbmt::Outbox.error_tracker).to receive(:error)

      expect(result).to be_failure
      expect(result.failure).to include("not found")
    end
  end

  context "when handler fails" do
    let(:handler) do
      Class.new do
        extend Dry::Monads[:result]

        def self.call(_payload, _metadata)
          Failure("error message")
        end
      end
    end

    it "returns error" do
      allow_any_instance_of(DeadLetter).to receive(:handler).and_return(handler)
      expect(Sbmt::Outbox.logger).to receive(:log_failure)
      expect(Sbmt::Outbox.error_tracker).to receive(:error)

      expect { result }.not_to change(DeadLetter, :count)
      expect(result).to be_failure
    end
  end
end
