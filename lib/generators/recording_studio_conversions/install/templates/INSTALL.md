RecordingStudioConversions install complete.

Next steps:

1. Review config/initializers/recording_studio_conversions.rb and set any required options.
2. If you use environment-specific settings, create config/recording_studio_conversions.yml.
3. Install the engine migrations with `bin/rails generate recording_studio_conversions:migrations`.
4. Apply the migrations with `bin/rails db:migrate`.
5. Run `bin/rails tailwindcss:build` if you use Tailwind CSS.
6. Mount routes are added at the configured mount path. Adjust auth, layout, and current actor integration to match your host app.
7. Keep strict recordable declarations enabled and add `recording_studio_recordable(...)` to every configured recordable before running `RecordingStudio.validate_recordable_declarations!`.