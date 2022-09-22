# frozen_string_literal: true

describe "rake outbox:process_dead_letters" do
  subject(:task) { Rake::Task["outbox:process_dead_letters"] }

  let!(:letter_a) { Fabricate(:dead_letter) }
  let!(:letter_b) { Fabricate(:dead_letter) }

  before do
    task.reenable
  end

  it "processes all dead letters" do
    expect(Sbmt::Outbox::ProcessDeadLetter).to receive(:call).with(DeadLetter, letter_a.id)
    expect(Sbmt::Outbox::ProcessDeadLetter).to receive(:call).with(DeadLetter, letter_b.id)

    task.invoke("DeadLetter")
  end

  context "when processing specific letter" do
    it "processes that item only" do
      expect(Sbmt::Outbox::ProcessDeadLetter).not_to receive(:call).with(DeadLetter, letter_a.id)
      expect(Sbmt::Outbox::ProcessDeadLetter).to receive(:call).with(DeadLetter, letter_b.id)

      task.invoke("DeadLetter", letter_b.id)
    end
  end
end
