# frozen_string_literal: true

describe Sbmt::Outbox::CreateDeadLetter do
  let(:result) { described_class.call(DeadLetter, **params) }
  let(:params) do
    {
      proto_payload: "test-payload",
      topic_name: "test-topic",
      metadata: {headers: {"Outbox-Name" => "test-outbox"}},
      error: "test error"
    }
  end

  context "when all params are valid" do
    it "creates dead letter" do
      expect { result }.to change(DeadLetter, :count).by(1)

      expect(result.value!).to have_attributes(
        proto_payload: "test-payload",
        topic_name: "test-topic",
        metadata: {"headers" => {"Outbox-Name" => "test-outbox"}},
        error: "test error"
      )
    end

    it "tracks metrics" do
      expect { result }.to increment_yabeda_counter(Yabeda.dead_letters.error_counter)
        .with_tags(name: "test-outbox", topic: "test-topic")
    end
  end

  context "when error is an exception object" do
    it "saves exception message" do
      params[:error] = StandardError.new("test exception message")
      expect(result.value!).to have_attributes(error: "test exception message")
    end
  end

  context "when some params are invalid" do
    before do
      params[:proto_payload] = nil
    end

    it "doesn't create dead letter" do
      expect { result }.not_to change(DeadLetter, :count)
      expect(result).to be_failure
    end

    it "tracks metrics" do
      expect { result }.to increment_yabeda_counter(Yabeda.dead_letters.error_counter)
        .with_tags(name: "test-outbox", topic: "test-topic")
    end
  end
end
