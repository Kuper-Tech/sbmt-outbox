# frozen_string_literal: true

Sbmt::Outbox::Engine.routes.draw do
  root to: "root#index"

  namespace :api, defaults: {format: :json} do
    resources :outbox_classes, only: [:index, :show, :update, :destroy]
    resources :inbox_classes, only: [:index, :show, :update, :destroy]
  end
end
