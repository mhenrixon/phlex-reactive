# frozen_string_literal: true

module Phlex
  module Reactive
    module Component
      # The view-side helper surface of Component (issue #115): the reply/js
      # builders, the root-element attribute helpers (reactive_attrs/
      # reactive_root), the trigger builders (on/on_client) with their hint
      # vocabularies, the form-binding helpers (reactive_field/input/select/
      # text/busy_on/reactive_compute_attrs), and the nested-attributes
      # helpers. Everything a view_template spreads or calls — no registries,
      # no signing (those live in DSL and Identity).
      module Helpers
        extend ActiveSupport::Concern

        # The acting client's SSE connection id during the current action (nil
        # outside an action, or when the client isn't subscribed to a stream).
        # Pass it as `exclude:` when broadcasting from an action so the actor
        # doesn't receive the echo of its own change — it already gets the
        # action's HTTP response:
        #
        #   def send_message(body:)
        #     msg = ChatMessage.create!(room: @room, body:)
        #     ChatMessage::Item.broadcast_append_to("chat", @room,
        #       target: "messages", model: msg, exclude: reactive_connection_id)
        #   end
        def reactive_connection_id
          Phlex::Reactive.current_connection_id
        end

        # Subject-bound reply builder — the preferred way to control an action's
        # reply. `reply.replace.flash(:error, msg)` reads cleaner than
        # `Phlex::Reactive::Response.replace(self).flash(:error, msg)`: the
        # component is the implicit subject (no `self` to thread) and there's no
        # constant to qualify (reply is a method, so a namespaced component needs
        # no `Response = …` alias). It returns the same immutable Response the
        # endpoint reads, so chaining and the legacy return-value contract are
        # unchanged. See Phlex::Reactive::Reply.
        #
        #   def archive       = reply.remove
        #   def go_home       = reply.redirect("/todos")
        #   def update(name:) = (@account.update!(name:); reply.morph)
        def reply
          Phlex::Reactive::Reply.new(self)
        end

        # An empty client-side op chain (issue #95) — the starting point for
        # on_client's DOM commands, mirroring how `reply` starts a Response chain:
        #   button(**on_client(:click, js.toggle("#menu"))) { "Menu" }
        # Immutable: each verb returns a new chain, so reuse never leaks ops.
        def js
          Phlex::Reactive::JS.new
        end

        # Root-element attributes: marks the element reactive and carries the
        # signed identity token. Spread onto the root:
        #   div(id:, **reactive_attrs) { ... }
        def reactive_attrs
          data = {
            controller: "reactive",
            reactive_token_value: reactive_token
          }
          # Client debug mode (issue #108): stamp the flag so the generic controller
          # console.groups every dispatch. STRING "true", not boolean — Phlex renders
          # a boolean-true attr VALUELESS, which getAttribute reads as "" (falsy in
          # JS), so the client's attr check would never fire (the on()/warn_unsaved
          # precedent). Off by default → no key, no string, zero client surface.
          data[:reactive_debug] = "true" if Phlex::Reactive.debug
          { data: }
        end

        # The WHOLE reactive root in one spread (issue #48). reactive_attrs alone
        # doesn't emit `id:`, so `id:` and `data-controller="reactive"` can land on
        # DIFFERENT elements — putting `id:` on a child leaves the controller root's
        # `id` empty, which silently breaks token threading (the client self-matches
        # its next token by `this.element.id`) and 403s on the next action.
        #
        # reactive_root binds the id to the SAME element as reactive_attrs, so the
        # footgun is unbuildable:
        #   div(**reactive_root) { ... }                       # id + controller + token
        #   div(**reactive_root(class: "card")) { ... }        # add your own attrs
        #
        # mix deep-merges, so overrides add `class:`/`data:` without clobbering the
        # controller/token data: (a bare data: would). The id is resolved separately
        # (an explicit override wins as a clean replace, not a `mix` string-concat —
        # mix would join two String ids into "default override").
        #
        # `track_dirty:`/`warn_unsaved:` (issue #103) are CONSUMED here — deleted
        # from overrides BEFORE the mix — because reactive_root treats every leftover
        # kwarg as a literal HTML attribute override (only :id is special-cased), so
        # an unconsumed `track_dirty: true` would render a bogus `track-dirty="true"`
        # attribute. track_dirty mixes the trackDirty descriptor onto the root's
        # data-action (mix token-joins, so a caller's own data-action survives);
        # warn_unsaved emits the marker the client reads to arm the navigate-away
        # guard (STRING "true" — a boolean-true attr renders valueless, which the
        # client's param reader sees as "" → falsy).
        def reactive_root(**overrides)
          root_id = overrides.delete(:id) || id
          track_dirty = overrides.delete(:track_dirty)
          warn_unsaved = overrides.delete(:warn_unsaved)

          attrs = mix({ **reactive_attrs }, overrides, { id: root_id })
          attrs = mix(attrs, { data: { action: "input->reactive#trackDirty" } }) if track_dirty
          attrs = mix(attrs, { data: { reactive_warn_unsaved: "true" } }) if warn_unsaved
          attrs
        end

        # Attributes for an element that triggers an action.
        #   button(**on(:toggle)) { "○" }
        #   form(**on(:save, event: "submit")) { ... }
        #   input(**on(:update, event: "input", debounce: 300))  # live-as-you-type
        #
        # Extra keyword args become explicit params merged over collected form
        # fields. For click triggers we force type="button" so a bare button
        # inside a <form> can't submit it and cause a full-page navigation.
        #
        # `debounce:` (milliseconds) coalesces rapid events (e.g. keystrokes on an
        # "input" trigger) into ONE round trip fired after the quiet period — so
        # live-update-as-you-type doesn't POST per keystroke. A blur flushes a
        # pending dispatch so the last edit is never dropped. Omit it for the
        # immediate-dispatch default.
        #
        # `confirm:` (a message string) gates the action behind a confirmation
        # prompt (issue #52). Destructive reactive triggers can't use Hotwire's
        # `data-turbo-confirm` — the reactive controller calls preventDefault and
        # enqueues the POST itself, so Turbo's confirm handling never runs. The
        # client shows window.confirm(message) FIRST and bails before any
        # enqueue/debounce if the user declines (and prevents the native default so
        # a `submit` trigger can't navigate on cancel). Omit it for no prompt.
        #   button(**on(:destroy, confirm: "Really delete this item?")) { "Delete" }
        #
        # `event:` is interpolated verbatim into the Stimulus action descriptor
        # (`#{event}->reactive#dispatch`), so any Stimulus event string works —
        # including its native KEYBOARD FILTERS. Pass `event: "keydown.enter"` for
        # Enter-to-submit or `event: "keydown.esc"` for Escape-to-cancel, and the
        # action fires only on that key — no separate option, no client code, and
        # `key` stays free as an ordinary action-param name (on(:switch, key: …)):
        #   input(**on(:add, event: "keydown.enter"))      # Enter submits
        #   button(**on(:cancel, event: "keydown.esc"))     # Escape cancels
        #
        # `listnav:` (a CSS selector for the option elements) adds keyboard list
        # navigation to a search/combobox trigger (issue #72). It appends Stimulus
        # keyboard filters to the SAME element's data-action so Arrow Up/Down move a
        # client-side highlight among the options, Enter picks the highlighted one
        # (clicking its own reactive trigger — so selection stays a signed action),
        # and Escape clears — all with NO server round trip for the highlight (the
        # controller's listnav* handlers, like #recompute). Omit it for no nav.
        #   input(**on(:search, event: "input", debounce: 300, listnav: "[role=option]"))
        # The verbatim JSON for an empty explicit-params payload. The common
        # trigger (on(:increment), no params) hits this on EVERY render — skipping
        # params.to_json (which re-serializes {} to the same "{}" each time) avoids
        # a per-render allocation while keeping the wire format byte-identical.
        EMPTY_PARAMS_JSON = "{}"

        # The keyboard filters appended to a listnav trigger's data-action. Each is
        # a client-only handler (no POST) except Enter, which clicks the highlighted
        # option's own reactive trigger. Stimulus binds these natively.
        LISTNAV_ACTIONS = [
          "keydown.down->reactive#listnavNext",
          "keydown.up->reactive#listnavPrev",
          "keydown.enter->reactive#listnavPick",
          "keydown.esc->reactive#listnavClose"
        ].freeze

        # Event modifiers (issue #80) — window:, once:, outside:, throttle: are
        # RESERVED keyword names on on() (no longer usable as free action params):
        #
        # `window: true` binds the trigger to the window (Stimulus's native
        # `@window` descriptor suffix) — for page-level events like scroll/resize.
        # `once: true` appends Stimulus's `:once` option, so the trigger fires at
        # most one round trip and then unbinds. Both are pure descriptor
        # composition. A window-bound trigger is NOT preventDefault-ed by the
        # client (it would kill every native click/submit on the page), and it
        # skips the forced type="button" (it isn't an in-form button trigger).
        #
        # `outside: true` fires the action only for events OUTSIDE this
        # component's ROOT (containment against the reactive root element) — the
        # close-a-dropdown-on-outside-click pattern. It implies `window: true`;
        # an event inside the root is a complete client-side no-op:
        #   div(**mix(reactive_root, on(:close_menu, outside: true))) { ... }
        #
        # `throttle:` (milliseconds) rate-limits a hot trigger LEADING-EDGE: the
        # first event fires immediately, further events are suppressed until the
        # window elapses (scroll/mousemove). Mutually exclusive with `debounce:`
        # (trailing-edge) — passing both raises ArgumentError.
        #   div(**mix(reactive_root, on(:track, event: "scroll", window: true, throttle: 250)))
        #
        # `optimistic:` (issue #98) — a small, ALWAYS-REVERSIBLE vocabulary of
        # COSMETIC hints the client applies the instant the trigger fires and
        # REVERTS if the round trip fails, so a click/toggle gives instant feedback
        # instead of waiting a full round trip. Hints are visual only — never data,
        # never computed values (that would be client state). Supported ops in the
        # hint hash:
        #   * toggle_class:/add_class:/remove_class: — a class string or array,
        #     applied to the TRIGGER (default) or to a `to:` selector scoped to the
        #     root (`to: :root` targets the root element itself).
        #   * checked: :keep — for a click-bound checkbox/radio, the client SKIPS
        #     its unconditional preventDefault so the native flip happens now
        #     (today the morph never even lets it flip). On failure, the flip is
        #     reverted.
        #   * hide: true — hides the target immediately (the `hide: true` + a
        #     `reply.remove` action is the instant delete-a-row recipe: the hint
        #     hides it, the reply removes it; a failure snaps it back).
        # Success does NO cleanup: a reply that re-renders the root overwrites the
        # hint with server truth; a reply that does NOT re-render the root
        # (reply.remove / streams-only) LEAVES the hint standing — that's the
        # instant-delete working as intended.
        #   input(type: "checkbox", checked: @todo.done,
        #     **mix(on(:toggle, event: "change", optimistic: { checked: :keep }), name: "done"))
        #   button(**on(:destroy, confirm: "Delete?", optimistic: { hide: true, to: :root })) { "Delete" }
        # `loading:` / `disable_with:` (issue #99) — declarative per-trigger loading
        # states, Livewire's wire:loading + phx-disable-with without a Stimulus
        # controller. The moment the request is ENQUEUED (covering the queue wait,
        # not just the fetch), the trigger gets `data-reactive-busy="<action>"`, an
        # optional loading class, an optional disabled + text swap; all revert in a
        # guarded finally. `loading:` is a hash:
        #   * disable: true         — disable the trigger while pending
        #   * class: "…" / [ … ]    — a loading class string/array on the trigger
        #                             (or a `to:` selector scoped to the root)
        #   * text: "Saving…"       — swap the trigger's textContent while pending
        #   * to: :root / "sel"     — target the class/text at the root or a selector
        # `disable_with: "Saving…"` is the shorthand for
        # `{ disable: true, text: "Saving…" }` and merges over an explicit `loading:`
        # (its text/disable win). Both become RESERVED on() kwargs (CHANGELOG note,
        # like #80's four and #98's optimistic:) — no longer free action-param names.
        # The trigger/root also always carry `data-reactive-busy` for the whole
        # pending window regardless of these hints, so an app styles a spinner with
        # `[data-reactive-busy] .spinner { display: block }` and zero Ruby; see
        # busy_on for scoped indicators.
        #   button(**on(:save, disable_with: "Saving…")) { "Save" }
        #   button(**on(:destroy, confirm: "Sure?", loading: { class: "opacity-50" })) { "Delete" }
        def on(action_name, event: "click", debounce: nil, throttle: nil, confirm: nil, listnav: nil,
               window: false, once: false, outside: false, optimistic: nil, loading: nil, disable_with: nil,
               **params)
          # A typo'd or forgotten action renders fine and only surfaces as an
          # opaque 403 at CLICK time (the endpoint's default-deny). Under
          # verbose_errors (dev + test), fail loudly at RENDER time instead —
          # listing the declared actions — the same courtesy reactive_compute_attrs
          # gives an undeclared compute (issue #105). Placed FIRST, before any attr
          # building. Production (flag off) keeps the permissive emit: a stale page
          # after a deploy that removed an action must not 500 on render. This is a
          # dev-time aid, NOT the security boundary — default-deny stays the
          # SERVER's enforcement. on_client triggers are not declared actions (no
          # registry), so they are never checked here.
          #
          # The check applies ONLY to a component that declares actions of its own.
          # A component with an EMPTY registry is a cross-component dispatch helper
          # — a child row that renders a trigger for its CONTAINER's action and
          # sends the container's token (e.g. NotificationRowComponent → the list's
          # :dismiss). It can't self-validate against a registry it doesn't own, so
          # the guard would false-positive; skipping the empty case keeps the
          # pattern working while still catching a typo in a component that DOES
          # declare actions (the issue's target — on(:togle) where :toggle exists).
          # verbose_errors is checked FIRST so production (flag off) short-circuits
          # before touching the registry — zero added cost on the hot path.
          if Phlex::Reactive.verbose_errors &&
             (actions = self.class.reactive_actions).any? && !actions.key?(action_name.to_sym)
            raise Phlex::Reactive::Error,
              "#{self.class} has no declared action #{action_name.to_sym.inspect} " \
              "(declared: #{actions.keys.inspect})"
          end

          if debounce && throttle
            raise ArgumentError,
              "on(#{action_name.inspect}) got both debounce: and throttle: — they are mutually " \
              "exclusive (debounce is trailing-edge, throttle is leading-edge); pick one"
          end

          window_bound = window || outside
          action = "#{event}#{"@window" if window_bound}->reactive#dispatch#{":once" if once}"
          action = "#{action} #{LISTNAV_ACTIONS.join(" ")}" if listnav
          attrs = {
            data: {
              action:,
              reactive_action_param: action_name.to_s,
              reactive_params_param: params.empty? ? EMPTY_PARAMS_JSON : params.to_json
            }
          }
          attrs[:data][:reactive_debounce_param] = debounce if debounce
          attrs[:data][:reactive_throttle_param] = throttle if throttle
          attrs[:data][:reactive_confirm_param] = confirm if confirm
          attrs[:data][:reactive_listnav_option_param] = listnav if listnav
          attrs[:data][:reactive_optimistic_param] = optimistic_hint_json(optimistic, action_name) if optimistic
          if (loading_hint = loading_hint_json(loading, disable_with, action_name))
            attrs[:data][:reactive_loading_param] = loading_hint
          end
          # STRING "true", not boolean: Phlex renders a `true` attribute VALUELESS
          # (data-reactive-outside-param), which Stimulus's param reader sees as ""
          # — falsy in JS, so the guard silently never fires. The explicit ="true"
          # typecasts to a real boolean on the client.
          attrs[:data][:reactive_outside_param] = "true" if outside
          # The client decides preventDefault behavior from event.params (never by
          # sniffing the descriptor), so EVERY window binding flags the param.
          attrs[:data][:reactive_window_param] = "true" if window_bound
          # Force type="button" for click triggers so a bare button inside a <form>
          # can't submit it — EXCEPT when checked: :keep is declared: that hint's
          # whole point is to let a click-bound checkbox/radio flip natively, and a
          # forced type="button" would destroy the very control being toggled
          # (issue #98). The caller supplies the real type="checkbox"/"radio".
          attrs[:type] = "button" if event == "click" && !window_bound && !optimistic_keeps_native?(optimistic)
          attrs
        end

        # Attributes for a CLIENT-ONLY trigger (issue #95): binds a DOM event to a
        # chain of declarative DOM ops (Phlex::Reactive::JS) that the generic
        # controller's runOps action applies in the browser — NO token, NO params,
        # NO POST, ever. The zero-round-trip sibling of on():
        #
        #   button(**on_client(:click, js.toggle("#menu"))) { "Menu" }
        #   # tabs, one line per tab, no Stimulus controller:
        #   button(**on_client(:click, js.hide(".panel").show("#panel-2")))
        #
        # `window:`, `once:`, and `outside:` compose exactly like on()'s event
        # modifiers (#80): outside-click-to-close a dropdown is
        #   div(**mix(reactive_root, on_client(:click, js.hide("#menu"), outside: true)))
        # Window-bound triggers are never preventDefault-ed by the client and skip
        # the forced type="button".
        #
        # Ops are EPHEMERAL UI: any server re-render of the component (an action
        # reply, a broadcast, a morph) rebuilds from server state and resets
        # whatever they toggled — by design (the LiveView JS-commands caveat). Use
        # a signed action for state that must survive re-renders.
        #
        # Validation is loud: only a non-empty Phlex::Reactive::JS chain is
        # accepted — a dead trigger should fail at render, not no-op in the
        # browser.
        def on_client(event, ops, window: false, once: false, outside: false)
          unless ops.is_a?(Phlex::Reactive::JS)
            raise ArgumentError,
              "on_client expects a Phlex::Reactive::JS chain (e.g. js.toggle(\"#menu\")), " \
              "got #{ops.class}"
          end
          raise ArgumentError, "on_client(#{event.inspect}) got no ops — a dead trigger" if ops.empty?

          event = event.to_s
          window_bound = window || outside
          attrs = {
            data: {
              action: "#{event}#{"@window" if window_bound}->reactive#runOps#{":once" if once}",
              reactive_ops_param: ops.to_json
            }
          }
          # STRING "true", not boolean — same Phlex valueless-attribute trap as
          # on()'s flags above.
          attrs[:data][:reactive_outside_param] = "true" if outside
          attrs[:data][:reactive_window_param] = "true" if window_bound
          attrs[:type] = "button" if event == "click" && !window_bound
          attrs
        end

        # Bind a form control's `name` to an action param so its value travels with
        # the action — instead of hand-writing the magic `name: "value"` on every
        # input and silently getting no params when you forget it (issue #23).
        # Returns a Phlex attributes hash to spread onto any control:
        #   input(**reactive_field(:value, value: @record.name))
        #   select(**reactive_field(:status)) { ... }
        # Extra attrs merge over the binding; an explicit name: still wins (escape
        # hatch). The trigger (on(:save)) stays on the button, not the field — so
        # focusing the input doesn't dispatch and collapse edit mode.
        #
        # `dirty: true` (issue #103) wires the field to the generic controller's
        # trackDirty action, so a change re-scans this reactive root's owned fields
        # and marks the changed ones `data-reactive-dirty` (and the root with a
        # count). NO client state is shipped — the baseline is the DOM's own
        # `defaultValue`/`defaultChecked`/`defaultSelected`, i.e. the attributes from
        # the last server render; dirty = current ≠ default. It deep-merges the
        # descriptor via mix, so a caller's own data-action is token-joined, not
        # clobbered (CLAUDE.md Never-Do #8 — combining with other data:/on() still
        # needs mix at the call site).
        def reactive_field(param, dirty: false, **attrs)
          binding_attrs = { name: param.to_s, **attrs }
          return binding_attrs unless dirty

          mix(binding_attrs, { data: { action: "input->reactive#trackDirty" } })
        end

        # Render an <input> already bound to an action param (issue #23). Sugar for
        # input(**reactive_field(param, **attrs)); the value/type/etc. pass through.
        #   reactive_input(:value, value: @record.name, type: "text")
        def reactive_input(param, **attrs)
          input(**reactive_field(param, **attrs))
        end

        # Mirror a compute output (or a declared input) into a TEXT NODE — a live
        # preview heading, a character counter, a "Hello, {name}" greeting (issue
        # #104). The text sibling of reactive_field: reactive_field binds a FORM
        # CONTROL; reactive_text binds a plain span the client writes via
        # textContent (XSS-safe by construction — never innerHTML).
        #
        #   h2 { reactive_text(:title_preview, @post.title) }
        #   small { reactive_text(:char_count) }
        #
        # The span carries data-reactive-text=<name> and NO `name` attribute, so
        # #collectFields never sweeps it into the POSTed params. `initial` seeds the
        # first paint — the SERVER render must seed the same derived value the
        # reducer would, or a morph repaints stale text (same reconcile contract
        # reactive_compute documents). Extra attrs merge over the binding.
        def reactive_text(name, initial = nil, **attrs)
          span(**mix({ data: { reactive_text: name.to_s } }, attrs)) { initial }
        end

        # Value-conditional visibility (issue #161) — the x-show / data-show /
        # wire:show equivalent, entirely client-side. Spread onto the element to
        # show/hide; it declares which OWNED field controls it plus ONE literal
        # predicate, and the generic controller toggles the `hidden` attribute
        # from the field's CURRENT value on every input/change — no round trip,
        # no token, no bespoke Stimulus controller:
        #
        #   div(**reactive_show(:mode, not: "off"))        { "details" }
        #   div(**reactive_show(:kind, equals: "premium")) { "premium panel" }
        #   div(**reactive_show(:size, in: %w[l xl]))      { "surcharge note" }
        #   div(**reactive_show(:gift, equals: true))      { "gift message" }
        #
        # Exactly one predicate — equals:, not:, or in: (a list) — and every
        # value is STRINGIFIED for a literal match against the field's value
        # (a checkbox compares its checked state as "true"/"false", so
        # `equals: true` is the checkbox form; a radio group reads the checked
        # radio's value). This is a DECLARED LITERAL MATCH, never an expression
        # — there is no eval surface (default-deny, like the op vocabulary).
        #
        # Scope: presentational only, strictly less powerful than the js ops —
        # it reads an owned field (#15 ownership) and toggles `hidden` on an
        # owned element. The client seeds visibility at connect and reconciles
        # after a morph; render the initial `hidden:` yourself (from the same
        # server state that renders the field) to avoid a first-paint flash.
        # Extra attrs deep-merge over the binding (mix), like reactive_field.
        def reactive_show(field, **options)
          predicates = options.slice(*SHOW_PREDICATE_KEYS)
          attrs = options.except(*SHOW_PREDICATE_KEYS)
          unless predicates.size == 1
            raise ArgumentError,
              "reactive_show(#{field.inspect}) needs exactly one predicate — equals:, not:, or " \
              "in: — got #{predicates.keys.inspect}"
          end

          key, value = normalize_show_predicate(predicates, "reactive_show(#{field.inspect})").first
          data = { reactive_show_field: field.to_s }
          data[:"reactive_show_#{key}"] = key == "in" ? value.to_json : value

          mix({ data: }, attrs)
        end

        # CROSS-ROOT value-conditional visibility (issue #164) — the visibility
        # parallel to reactive_compute's `mirror:` (#159). A plain reactive_show
        # is root-scoped by design (#15), so it can't express "this control
        # drives elements ELSEWHERE on the page" — a nav tab, a panel in another
        # tab pane, a sidebar note. reactive_show_targets is the declared,
        # id-allowlisted escape: the component that OWNS the field declares
        # which outside ids it governs. Spread it on the ROOT (mix alongside
        # reactive_root — the client reads it off the controller element):
        #
        #   div(**mix(reactive_root, reactive_show_targets(:mode,
        #     "#advanced-tab"   => { equals: "advanced" },
        #     "#advanced-panel" => { equals: "advanced" },
        #     "#basic-note"     => { not: "advanced" })))
        #
        # Same posture as mirror: — opt-in and declared, never implicit (a plain
        # reactive_show stays root-isolated); targets are SINGLE ID SELECTORS
        # only, enforced here at declare time AND warn-and-skipped by the client
        # interpreter (two-sided default-deny); the predicate is the same
        # literal-only reactive_show vocabulary (exactly one of equals:/not:/
        # in:, no expressions); and the toggle is `hidden` only — no innerHTML,
        # no attribute freedom. The FIELD read stays owned (#15): you can only
        # drive outside visibility from a field this root owns. A target id not
        # on the page is silently skipped (an unrendered tab pane is normal).
        #
        # ONE call per root. Phlex `mix` space-joins duplicate STRING data
        # values, so a second call's JSON would concatenate into an unparseable
        # attr and the client would drop BOTH maps (it warns when that
        # happens). Several fields therefore go in ONE call via the hash form:
        #
        #   reactive_show_targets(mode: { "#advanced-tab" => { equals: "advanced" } },
        #                         kind: { "#premium-note" => { not: "basic" } })
        def reactive_show_targets(field, targets = nil)
          field_maps = targets.nil? ? field : { field => targets }
          unless field_maps.is_a?(Hash) && field_maps.any?
            raise ArgumentError,
              "reactive_show_targets needs at least one target " \
              "(:field, \"#id\" => { equals:/not:/in: ... }), got #{field_maps.inspect}"
          end

          normalized = field_maps.to_h do |name, map|
            # Catch the forgotten-field-name misuse — reactive_show_targets(
            # "#id" => {…}) — before the per-target validation turns it into a
            # baffling "predicate" error.
            if name.to_s.start_with?("#")
              raise ArgumentError,
                "reactive_show_targets: #{name.inspect} looks like a target selector, not a field " \
                "name — call reactive_show_targets(:field, #{name.inspect} => { ... })"
            end

            [name.to_s, normalize_show_target_map(name, map)]
          end

          { data: { reactive_show_targets: normalized.to_json } }
        end

        # Scoped busy indicator (issue #99). Marks an element so the generic
        # controller toggles `data-reactive-busy` on it ONLY while `action` is in
        # flight — the scoped sibling of the always-on `data-reactive-busy` the
        # trigger and root carry. Spread onto any element inside the reactive root;
        # style it with `[data-reactive-busy] { … }` and zero Ruby:
        #   span(**busy_on(:save), class: "spinner hidden")
        def busy_on(action)
          { data: { reactive_busy_on: action.to_s } }
        end

        # Data attributes declaring a client-side compute for the root element.
        # Spread ALONGSIDE reactive_root so the generic controller can find the
        # reducer and the named input/output fields inside this root:
        #   div(**mix(reactive_root, reactive_compute_attrs(:payment_split))) { … }
        #
        # It emits the reducer key plus the input/output field names as JSON so the
        # client runs the reducer on `input`, writes the outputs with no round trip,
        # then the debounced POST reconciles from the server reply. Raises for an
        # undeclared compute — a silent no-op would leave the field wiring dead.
        def reactive_compute_attrs(name)
          definition = self.class.reactive_compute_def(name)
          raise Error, "#{self.class} has no reactive_compute #{name.inspect}" unless definition

          data = {
            reactive_compute_reducer_param: definition.reducer,
            reactive_compute_inputs_param: compute_inputs_param(definition),
            reactive_compute_outputs_param: definition.outputs.map(&:to_s).to_json
          }
          # Declared cross-root text mirrors (issue #159) ride as a JSON object of
          # name → [id selectors]; omitted entirely when undeclared so the shipped
          # wire stays byte-identical.
          data[:reactive_compute_mirror_param] = compute_mirror_param(definition) if definition.mirror

          { data: }
        end

        # The mirror param wire (issue #159): { "sum_a" => ["#sum_a"], … } — the
        # values are ALWAYS arrays so the client parses one uniform shape.
        def compute_mirror_param(definition)
          definition.mirror.transform_keys(&:to_s).to_json
        end

        # The inputs param wire (issue #104). Untyped (array form) → a JSON ARRAY of
        # names, byte-identical to the shipped wire so the client keeps its numeric
        # coercion. Typed (hash form) → a JSON OBJECT of name→type
        # ({"title":"string","qty":"number"}) so the client reads a :string raw and
        # coerces a :number through Number.
        def compute_inputs_param(definition)
          types = definition.input_types
          return definition.inputs.map(&:to_s).to_json if types.nil?

          definition.inputs.to_h { [it.to_s, types[it].to_s] }.to_json
        end

        # Render a <select> bound to an action param (issue #23). The options block
        # is the element's content, so the awkward FormBuilder positional split
        # (where name: lands after the options/html-options args) goes away:
        #   reactive_select(:status) { @statuses.each { |s| option(value: s, selected: s == @record.status) { s } } }
        def reactive_select(param, **attrs, &)
          select(**reactive_field(param, **attrs), &)
        end

        # Map a declared nested param onto Rails' <assoc>_attributes, carrying the
        # existing associated record's id so accepts_nested_attributes_for matches
        # it IN PLACE instead of building a second one (issue #24). Returns the
        # update hash; pass it to update!:
        #   def save(address:) = nested_update!(:address, address)
        # The id is only added when the association already exists, so the first
        # save (no associated record yet) creates one cleanly. The given attrs are
        # not mutated.
        def nested_attributes(association, attrs)
          merged = attrs.dup
          existing = reactive_record_for_nested.public_send(association)
          merged[:id] = existing.id if existing

          { "#{association}_attributes": merged }
        end

        # Map a nested param onto <assoc>_attributes (with id preservation) AND
        # apply it to the component's record in one call (issue #24). Extra keyword
        # attributes update alongside the association.
        #   def save(address:, name:) = nested_update!(:address, address, name:)
        def nested_update!(association, attrs, **extra)
          reactive_record_for_nested.update!(**nested_attributes(association, attrs), **extra)
        end

        # The declared reactive_show predicates (issue #161): a literal match on
        # the controlling field's current value. Exactly one per binding —
        # enforced loudly at render (a dead binding must not no-op in the
        # browser). `not`/`in` are Ruby keywords, so they arrive via **options
        # rather than named kwargs.
        SHOW_PREDICATE_KEYS = %i[equals not in].freeze

        # The declared optimistic-hint class ops (issue #98): the cosmetic class
        # vocabulary the client applies instantly and reverts on failure. Enforced
        # at build time in optimistic_hint_json (default-deny — a dead hint fails
        # at render, not silently in the browser). Each carries a class string or
        # array; hide/checked are flags with a fixed shape.
        OPTIMISTIC_CLASS_OPS = %w[toggle_class add_class remove_class].freeze

        private

        # Normalize + validate ONE field's target map (issue #164): each key a
        # single id selector (loud raise — the declare-time half of the
        # two-sided default-deny), each value one literal predicate. Shared by
        # both reactive_show_targets call forms.
        def normalize_show_target_map(field, targets)
          unless targets.is_a?(Hash) && targets.any?
            raise ArgumentError,
              "reactive_show_targets(#{field.inspect}) needs at least one target " \
              "(\"#id\" => { equals:/not:/in: ... }), got #{targets.inspect}"
          end

          targets.to_h do |selector, predicate|
            selector = selector.to_s
            unless selector.match?(DSL::MIRROR_ID_SELECTOR)
              raise ArgumentError,
                "reactive_show_targets(#{field.inspect}) target #{selector.inspect} must be a single " \
                "ID selector (\"#id\") — cross-root visibility is id-allowlisted, like mirror: (#159)"
            end

            context = "reactive_show_targets(#{field.inspect}) target #{selector.inspect}"
            [selector, normalize_show_predicate(predicate.is_a?(Hash) ? predicate : {}, context)]
          end
        end

        # Validate ONE declared literal show predicate (issues #161/#164) and
        # return its wire form — { "equals" => "v" } / { "not" => "v" } /
        # { "in" => ["a", …] } (a real array: reactive_show JSON-encodes it into
        # its own attr; the reactive_show_targets map embeds it directly).
        # Shared by both helpers so the vocabulary and the loud validation can
        # never drift. `context` names the call site in the error.
        def normalize_show_predicate(predicates, context)
          unless predicates.size == 1 && SHOW_PREDICATE_KEYS.include?(predicates.keys.first)
            raise ArgumentError,
              "#{context} needs exactly one predicate — equals:, not:, or in: — " \
              "got #{predicates.keys.inspect}"
          end

          key, value = predicates.first
          return { key.to_s => value.to_s } unless key == :in

          list = Array(value).map(&:to_s)
          raise ArgumentError, "#{context} in: needs at least one value" if list.empty?

          { "in" => list }
        end

        # True when the hint declares checked: :keep — the click-bound
        # checkbox/radio case that must SKIP the forced type="button" so the native
        # control (and its native flip) survives (issue #98). Accepts symbol or
        # string keys/values; nil-safe for the no-hint hot path.
        def optimistic_keeps_native?(optimistic)
          return false unless optimistic.is_a?(Hash)

          value = optimistic[:checked] || optimistic["checked"]
          value.to_s == "keep"
        end

        # Normalize + validate the optimistic hint hash, returning its JSON wire
        # form (data-reactive-optimistic-param). `to: :root` becomes the same
        # "@root" sentinel the js op builder uses so the client resolves it
        # uniformly. Unknown keys, a bad `checked:` value, or a non-hash raise —
        # a hint that can't apply must fail loudly at render.
        def optimistic_hint_json(optimistic, action_name)
          unless optimistic.is_a?(Hash)
            raise ArgumentError,
              "on(#{action_name.inspect}) optimistic: must be a Hash of visual hints " \
              "(e.g. { checked: :keep } or { hide: true, to: :root }), got #{optimistic.class}"
          end

          hint = {}
          optimistic.each do |key, value|
            case key.to_s
            when *OPTIMISTIC_CLASS_OPS
              hint[key.to_s] = Array(value).map(&:to_s)
            when "hide"
              hint["hide"] = value ? true : false
            when "checked"
              unless value.to_s == "keep"
                raise ArgumentError,
                  "on(#{action_name.inspect}) optimistic checked: only supports :keep " \
                  "(flip the native control, revert on failure), got #{value.inspect}"
              end
              hint["checked"] = "keep"
            when "to"
              hint["to"] = value == :root ? Phlex::Reactive::JS::ROOT_SENTINEL : value.to_s
            else
              raise ArgumentError,
                "on(#{action_name.inspect}) got an unknown optimistic hint #{key.inspect} — " \
                "supported: toggle_class/add_class/remove_class, checked: :keep, hide: true, to:"
            end
          end

          hint.to_json
        end

        # Normalize + validate the loading hint (issue #99), returning its JSON wire
        # form (data-reactive-loading-param) or nil when neither loading: nor
        # disable_with: is given (the bare on() hot path stays untouched).
        # disable_with: "Saving…" expands to { disable: true, text: … } and MERGES
        # over an explicit loading: hash — its text/disable win. `to: :root` becomes
        # the "@root" sentinel the js op builder uses so the client resolves targets
        # uniformly. An unknown key or a non-hash loading: raises — a dead hint must
        # fail loudly at render, not silently in the browser (default-deny).
        def loading_hint_json(loading, disable_with, action_name)
          return nil if loading.nil? && disable_with.nil?

          source = loading || {}
          unless source.is_a?(Hash)
            raise ArgumentError,
              "on(#{action_name.inspect}) loading: must be a Hash of loading hints " \
              "(e.g. { disable: true, class: \"opacity-50\", text: \"Saving…\" }), got #{loading.class}"
          end

          hint = {}
          source.each do |key, value|
            case key.to_s
            when "class"
              hint["class"] = Array(value).map(&:to_s)
            when "disable"
              hint["disable"] = value ? true : false
            when "text"
              hint["text"] = value.to_s
            when "to"
              hint["to"] = value == :root ? Phlex::Reactive::JS::ROOT_SENTINEL : value.to_s
            else
              raise ArgumentError,
                "on(#{action_name.inspect}) got an unknown loading hint #{key.inspect} — " \
                "supported: disable:, class:, text:, to:"
            end
          end

          # disable_with: "Saving…" ≡ { disable: true, text: … }, applied AFTER the
          # explicit loading: hash so it wins on both keys (the shorthand is the
          # more specific intent when a caller passes both).
          if disable_with
            hint["disable"] = true
            hint["text"] = disable_with.to_s
          end

          hint.to_json
        end

        # The component's record, for the nested-attributes helpers. Requires a
        # declared reactive_record (the nested helper only makes sense for a
        # record-backed component).
        def reactive_record_for_nested
          key = self.class.reactive_record_key
          raise Error, "#{self.class} must declare `reactive_record` to use nested_update!/nested_attributes" unless key

          instance_variable_get(:"@#{key}")
        end
      end
    end
  end
end
