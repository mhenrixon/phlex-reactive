# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# Client-side compute reducers (reactive_compute). Registered on load in
# application.js via setComputeReducer.
pin_all_from "app/javascript/reducers", under: "reducers"
