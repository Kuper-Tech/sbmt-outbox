# frozen_string_literal: true

describe Sbmt::Outbox::Middleware::Runner do
  it "works with an empty stack" do
    instance = described_class.new([])
    expect { instance.call {} }.not_to raise_error
  end

  it "calls classes in the same order as given" do
    a = Class.new do
      def call(args)
        args[:result] << "A"
        yield
        args[:result] << "A"
      end
    end

    b = Class.new do
      def call(args)
        args[:result] << "B"
        yield
        args[:result] << "B"
      end
    end

    args = {result: []}
    instance = described_class.new([a, b])
    instance.call(args) { args[:result] << "C" }
    expect(args[:result]).to eq %w[A B C B A]
  end
end
