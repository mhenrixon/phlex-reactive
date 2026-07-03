// A no-op Stimulus base class for the client BENCH suite ONLY.
//
// `rake bench:client` runs the benches via a plain `bun run` (NOT `bun test`,
// which mock.modules @hotwired/stimulus). The real @hotwired/stimulus package is
// not a devDependency here — the benches only need the controller's own public
// methods (dispatch, recompute), so we alias @hotwired/stimulus (see the
// tsconfig `paths`) to this one-line base class: enough for `class extends
// Controller {}` to load. Nothing from Stimulus's runtime (values, targets,
// lifecycle) is exercised by the benched paths.
export class Controller {
  constructor() {}
}
