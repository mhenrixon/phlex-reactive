// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)

// The single generic controller behind every reactive Phlex component. The
// phlex-reactive engine auto-pins it for importmap apps; we register it EAGERLY
// (never lazyLoad) so a fast first click after page load can't miss connect().
import ReactiveController from "phlex/reactive/reactive_controller"
application.register("reactive", ReactiveController)
