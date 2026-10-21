# frozen_string_literal: true

class AttributionInspectorController < ApplicationController
  before_action :local_only!

  def show
    @visitor_id = RecordingStudioConversions::VisitorId.from_request(request)
    @observations = RecordingStudioConversions::AttributionObservation.order(captured_at: :desc, created_at: :desc)
    @links = RecordingStudioConversions::IdentityLink.order(linked_at: :desc, created_at: :desc)
    @consents = RecordingStudioConversions::ConsentRecord.order(recorded_at: :desc, created_at: :desc)
    @categories = RecordingStudioConversions::ConsentLedger.consent_categories
    @users = users_by_id(@links, @consents)
    @root = current_root_recording
    @resolved = resolved_for(@visitor_id)
  end

  def consent
    RecordingStudioConversions.record_consent!(
      visitor_id: visitor_id,
      category: params[:category].to_s,
      granted: params[:granted] == "true",
      user_id: current_user.id
    )
    redirect_to attribution_inspector_path
  end

  def acquisition
    root = current_root_recording
    if root
      RecordingStudioConversions.record_acquisition_user!(root_recording_id: root.id, user_id: current_user.id)
    end
    redirect_to attribution_inspector_path
  end

  def create_user
    user = User.create!(
      email: params[:email].to_s.strip,
      password: params[:password].to_s,
      password_confirmation: params[:password].to_s,
      confirmed_at: Time.current
    )
    redirect_to attribution_inspector_path,
                notice: "Created #{user.email}. Sign out, then sign in as that user in this browser."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to attribution_inspector_path, alert: e.record.errors.full_messages.to_sentence
  end

  def destroy_attribution
    user_id = params[:user_id].to_s
    unless RecordingStudioConversions::IdentityLink.exists?(user_id: user_id, visitor_id: visitor_id)
      redirect_to attribution_inspector_path, alert: "That user is not linked to this device."
      return
    end

    RecordingStudioConversions.delete_attribution_for_user!(user_id)
    redirect_to attribution_inspector_path
  end

  private

  def local_only!
    raise ActionController::RoutingError, "not found" unless Rails.env.local?
  end

  def visitor_id
    RecordingStudioConversions::VisitorId.from_request(request)
  end

  def users_by_id(links, consents)
    ids = links.map(&:user_id) + consents.map(&:user_id)
    User.where(id: ids.compact.uniq).index_by { |user| user.id.to_s }
  end

  def resolved_for(visitor_id)
    return [] if visitor_id.blank?

    user_ids = RecordingStudioConversions::IdentityLink.where(visitor_id: visitor_id, confirmed: true).pluck(:user_id)
    RecordingStudioConversions::AcquisitionSubject.where(subject_id: user_ids).map do |subject|
      found = RecordingStudioConversions.attribution_for(root_recording_id: subject.root_recording_id)
      {
        root_id: subject.root_recording_id,
        subject_id: subject.subject_id,
        status: found.status,
        values: found.observations.map { |row| "#{row.field_name}=#{row.value}" }
      }
    end
  end
end
