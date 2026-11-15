# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

find_or_record_child = lambda do |recordable, root_recording, parent_recording|
  RecordingStudio::Recording.kept.find_by(
    root_recording: root_recording,
    parent_recording: parent_recording,
    recordable: recordable
  ) || RecordingStudio.record!(
    action: "created",
    recordable: recordable,
    root_recording: root_recording,
    parent_recording: parent_recording,
    actor: Current.actor
  ).recording
end

# Create the admin user
user = User.find_or_create_by!(email: "admin@admin.com") do |u|
  u.password = "Password"
  u.password_confirmation = "Password"
end
user.update!(confirmed_at: Time.current) if user.confirmed_at.nil?

# Create the workspace recordables
workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
accessible_workspace = Workspace.find_or_create_by!(name: "Client Workspace")
private_workspace = Workspace.find_or_create_by!(name: "Private Workspace")
folder = Folder.find_or_create_by!(name: "Product Docs")
page = Page.find_or_create_by!(title: "Getting Started")

previous_actor = Current.actor
Current.actor = user

begin
  # create_root_recording! is idempotent. root_recording_for only finds.
  root_recording = RecordingStudio.create_root_recording!(workspace, actor: user)
  accessible_root_recording = RecordingStudio.create_root_recording!(accessible_workspace, actor: user)
  private_root_recording = RecordingStudio.create_root_recording!(private_workspace, actor: user)

  [root_recording, accessible_root_recording, private_root_recording].each do |recording|
    next if RecordingStudioAccessible.authorized?(actor: user, recording: recording, role: :edit)

    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: user)
    next if result.success?
    next if RecordingStudioAccessible.authorized?(actor: user, recording: recording, role: :edit)

    raise result.error
  end

  folder_recording = find_or_record_child.call(folder, root_recording, root_recording)

  find_or_record_child.call(page, root_recording, folder_recording)
ensure
  Current.actor = previous_actor
end

puts "Seeded: admin@admin.com / Password"
puts "Seeded: Workspace '#{workspace.name}' with root recording ##{root_recording.id}"
puts "Seeded: Workspace '#{accessible_workspace.name}' with root recording ##{accessible_root_recording.id}"
puts "Seeded: Workspace '#{private_workspace.name}' with root recording ##{private_root_recording.id}"
puts "Seeded: Folder '#{folder.name}' and page '#{page.title}'"
