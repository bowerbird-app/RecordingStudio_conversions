class ApplicationController < ActionController::Base
  include RecordingStudio::RootSwitchable::ControllerSupport
  include RecordingStudio::UsesDefaultLayout

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  layout :application_layout

  before_action :authenticate_user!
  before_action :set_current_actor
  before_action :link_signed_in_identity

  private

  def application_layout
    devise_controller? ? "application" : "recording_studio/default_layout"
  end

  def set_current_actor
    Current.actor = current_user
  end

  def link_signed_in_identity
    return unless current_user

    RecordingStudioConversions::IdentityLinker.from_request(
      visitor_id: RecordingStudioConversions::VisitorId.from_request(request),
      user: current_user
    )
  end
end
