# frozen_string_literal: true

Rails.application.routes.draw do
  mount Sbmt::Outbox::Engine => "/outbox-ui"
end
