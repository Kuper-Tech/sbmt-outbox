# frozen_string_literal: true

begin
  require "schked"

  Schked.config.paths << Sbmt::Outbox::Engine.root.join("config", "schedule.rb")
rescue LoadError
  # optional dependency
end
