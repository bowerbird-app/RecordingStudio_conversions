module ApplicationHelper
  def dummy_page_nav(title:, back_url: nil, back_label: "Home")
    # The default layout paints content_for(:title) as a second page heading.
    # These screens already render their heading, so title is intentionally unused here.
    flat_pack_page_nav(round: true, style: :default, back_href: back_url, back_tooltip: back_label)

    recording_studio_page_nav_right do
      if Rails.env.local?
        concat render(
          FlatPack::Button::Component.new(
            text: "Attribution",
            style: :ghost,
            size: :md,
            href: attribution_inspector_path
          )
        )
      end
      concat recording_studio_root_switch_dropdown(style: :ghost, size: :md)
      concat render(
        FlatPack::Button::Component.new(
          text: "Sign out",
          style: :ghost,
          size: :md,
          href: main_app.destroy_user_session_path,
          data: { turbo_method: :delete }
        )
      )
    end
  end

  def delete_attribution_button(link)
    return if @visitor_id.blank? || link.visitor_id != @visitor_id

    form_with url: attribution_user_path(link.user_id), method: :delete do
      render FlatPack::Button::Component.new(
        text: "Delete attribution",
        type: "submit",
        style: :danger,
        size: :sm
      )
    end
  end
end
