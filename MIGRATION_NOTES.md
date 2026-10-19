# Migration Notes

## Current Requirements

- Ruby 3.3 or newer
- Rails 8.1 or newer
- Recording Studio 4.x (`~> 4.2` in the gemspec; dummy GitHub tag `v4.7.0`)
- Accessible dummy tag `v0.18.0`, Trashable dummy tag `v0.11.0` (`require: false`), and Root Switchable dummy tag `v0.9.0`
- FlatPack dummy tag `v0.1.196`
- Public RubyGems and GitHub access for dependency installation

## Verification

Install both bundles and run the complete gem and dummy app test path:

```bash
bundle install
BUNDLE_GEMFILE=test/dummy/Gemfile bundle install
bundle exec rake test:all
```

Run the dummy app from its directory for browser verification:

```bash
cd test/dummy
bin/dev
```

Use the [FlatPack repository](https://github.com/bowerbird-app/flatpack) and the live FlatPack demo linked from the top-level README for current component documentation.
