module ApplicationHelper
  def dummy_page_nav(title:, back_url: nil, back_label: "Home")
    recording_studio_page_nav(
      title: title,
      page_nav_back_url: back_url,
      page_nav_back_label: back_label
    )

    recording_studio_page_nav_right do
      if Rails.env.local?
        concat render(
          FlatPack::Button::Component.new(
            text: "Attribution",
            style: :ghost,
            size: :md,
            url: attribution_inspector_path
          )
        )
      end
      concat recording_studio_root_switch_dropdown(style: :ghost, size: :md)
      concat render(
        FlatPack::Button::Component.new(
          text: "Sign out",
          style: :ghost,
          size: :md,
          url: main_app.destroy_user_session_path,
          data: { turbo_method: :delete }
        )
      )
    end
  end

  def delete_attribution_button(link)
    return if @visitor_id.blank? || link.visitor_id != @visitor_id

    render FlatPack::Button::Component.new(
      text: "Delete attribution",
      href: attribution_user_path(link.user_id),
      method: :delete,
      style: :danger,
      size: :sm
    )
  end
end
