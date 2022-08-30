# frozen_string_literal: true

Fabricator(:dead_letter, from: "DeadLetter") do
  proto_payload { "test-proto-payload" }
  topic_name { "test-topic" }
  metadata do
    {
      headers: {
        "Outbox-Name" => "test-outbox",
        "Sequence-ID" => 1,
        "Created-At" => Time.current.to_datetime.rfc3339(6)
      }
    }
  end
end
