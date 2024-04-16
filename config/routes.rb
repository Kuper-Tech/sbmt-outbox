# frozen_string_literal: true

Sbmt::Outbox::Engine.routes.draw do
  root to: "root#index"

  namespace :api, defaults: {format: :json} do
    resources :outbox_items
    resources :inbox_items
  end
end
