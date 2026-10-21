# frozen_string_literal: true

RecordingStudioConversions::Engine.routes.draw do
  root "home#index"
  post "collection", to: "collection#create", as: :collection
  post "consent", to: "consent#create", as: :consent
  get "modules/:name", to: "modules#show", as: :browser_module,
                       constraints: { name: /[a-z0-9][a-z0-9_-]{0,48}/ }
end
