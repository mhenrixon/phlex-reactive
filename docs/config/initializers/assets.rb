# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = '1.0'

Rails.application.config.assets.paths << Rails.root.join("app", "assets", "builds")

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# The Bun + Tailwind CLI build writes the compiled daisyUI/Tailwind CSS to
# app/assets/builds/application.css; add it to the Propshaft load path so
# stylesheet_link_tag("application") serves it. (The source —
# app/assets/stylesheets/application.tailwind.css — is the CLI input, not a
# served asset.)
Rails.application.config.assets.paths << Rails.root.join('app/assets/builds')
Rails.application.config.assets.excluded_paths << Rails.root.join('app/assets/stylesheets')
