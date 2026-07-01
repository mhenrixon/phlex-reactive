// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"
import { eagerLoadControllersFrom, lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)

// docs-kit's sidebar controller (docs-nav): persists collapse state + scroll-spy.
// Auto-pinned by the docs-kit engine; lazy is fine (not latency-critical).
lazyLoadControllersFrom("docs_kit/controllers", application)

// The single generic controller behind every reactive Phlex component. The
// phlex-reactive engine auto-pins it for importmap apps; we register it EAGERLY
// (never lazyLoad) so a fast first click after page load can't miss connect().
import ReactiveController from "phlex/reactive/reactive_controller"
application.register("reactive", ReactiveController)
