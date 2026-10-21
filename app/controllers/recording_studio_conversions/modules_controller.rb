# frozen_string_literal: true

module RecordingStudioConversions
  class ModulesController < ApplicationController
    # Script tags are not XHR. Forgery protection would reject the module
    # response. Consent and the adapter name are the gate.
    skip_forgery_protection only: :show
    after_action :private_module_cache

    def show
      adapter = adapter_for(module_name)
      return head :not_found if adapter.nil?
      return head :forbidden unless permitted?(adapter)

      path = BrowserModules.find(module_name)
      return head :not_found if path.nil?

      send_file path, type: "text/javascript", disposition: "inline"
    end

    private

    def private_module_cache
      response.headers["Cache-Control"] = "private"
      response.headers["Vary"] = "Cookie"
    end

    def module_name
      params[:name].to_s
    end

    def permitted?(adapter)
      ConsentLedger.granted?(visitor_id: VisitorId.from_request(request), category: adapter.consent.category)
    end

    def adapter_for(name)
      RecordingStudioConversions.configuration.enabled_adapters.find do |adapter|
        adapter.consent.collection && adapter.browser_module.to_s == name
      end
    end
  end
end
