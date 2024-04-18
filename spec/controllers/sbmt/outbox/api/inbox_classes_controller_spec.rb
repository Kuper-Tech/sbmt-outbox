# frozen_string_literal: true

describe Sbmt::Outbox::Api::InboxClassesController do
  routes { Sbmt::Outbox::Engine.routes }

  let(:box_id) { InboxItem.box_name }

  describe "#index" do
    it "returns raw inbox items" do
      get :index

      expect(response).to be_successful
      data = response.parsed_body
      expect(data).not_to be_empty
      expect(data.pluck("id")).to include("inbox_item")
    end
  end

  describe "#show" do
    it "represents inbox item" do
      get :show, params: {id: box_id}

      expect(response).to be_successful
      expect(response.parsed_body["id"]).to eq box_id
    end
  end

  describe "#update" do
    it "updates API config for inbox item" do
      put :update, params: {id: box_id, inbox_item: {polling_enabled: "false"}}

      expect(response).to be_successful
      expect(response.parsed_body["id"]).to eq box_id
      expect(response.parsed_body["polling_enabled"]).to be false
    end
  end

  describe "#destroy" do
    it "deletes API config for inbox item" do
      delete :destroy, params: {id: box_id}

      expect(response).to be_successful
    end
  end
end
