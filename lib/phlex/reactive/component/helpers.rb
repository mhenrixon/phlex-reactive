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

        # Manually satisfy the verify_authorized guard (issue #168) for a bespoke
        # authorization check the interceptor can't see — a hand-rolled policy, a
        # feature flag, an ownership comparison that doesn't go through one of
        # Phlex::Reactive.authorization_methods:
        #
        #   def publish
        #     raise NotAllowed unless @post.author == Current.user
        #     mark_authorized!
        #     @post.update!(published: true)
        #   end
        #
        # Call it only AFTER your check passes — it asserts "I have authorized
        # this action." A no-op when verify_authorized is off.
        def mark_authorized!
          Phlex::Reactive::Authorization.mark!
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
          data = { controller: "reactive" }
          # A CLIENT-ONLY component (Phlex::Reactive::ClientBindings, issue #180)
          # has no Identity, so no token — the root is tokenless (show/filter/
          # compute need no signed round trip). reactive_token is private, so the
          # include-private `respond_to?` mirrors to_stream_token's guard.
          data[:reactive_token_value] = reactive_token if respond_to?(:reactive_token, true)
          # Client debug mode (issue #108): stamp the flag so the generic controller
          # console.groups every dispatch. STRING "true", not boolean — Phlex renders
          # a boolean-true attr VALUELESS, which getAttribute reads as "" (falsy in
          # JS), so the client's attr check would never fire (the on()/warn_unsaved
          # precedent). Off by default → no key, no string, zero client surface.
          data[:reactive_debug] = "true" if Phlex::Reactive.debug
          # Field-name scope (issue #180): the client prefixes bare binding field
          # names with `scope[...]`. Omitted entirely when undeclared — byte-stable
          # wire for unscoped components.
          if self.class.respond_to?(:reactive_scope) && (scope = self.class.reactive_scope)
            data[:reactive_scope] = scope.to_s
          end
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
          # A CLIENT-ONLY component (ClientBindings, issue #180) needs no #id —
          # there's no token to self-match by id. Use an explicit override, else
          # #id when the component defines one, else nothing (no id attr).
          root_id = overrides.delete(:id)
          root_id = id if root_id.nil? && respond_to?(:id)
          track_dirty = overrides.delete(:track_dirty)
          warn_unsaved = overrides.delete(:warn_unsaved)

          attrs = mix({ **reactive_attrs }, overrides)
          attrs = mix(attrs, { id: root_id }) unless root_id.nil?
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
        # Combobox keyboard navigation is the standalone reactive_listnav (issue
        # #181 removed the `on(…, listnav:)` kwarg — it duplicated reactive_listnav
        # while skipping its blank-selector validation). Compose it via mix:
        #   input(**mix(on(:search, event: "input", debounce: 300), reactive_listnav))
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
        # `busy:` (issue #181) — declarative per-trigger pending states, Livewire's
        # wire:loading + phx-disable-with without a Stimulus controller. It shares
        # optimistic:'s key vocabulary and normalizer; the ONLY difference is the
        # lifecycle: a busy: hint applies the moment the request is ENQUEUED
        # (covering the queue wait, not just the fetch) and reverts on SETTLE (any
        # completion), where optimistic: reverts only on FAILURE. `busy:` is a
        # String or a Hash:
        #   * "Saving…"             — String shorthand for { disable: true, text: … }
        #   * disable: true         — disable the trigger while pending
        #   * add_class:/remove_class:/toggle_class: "…" / [ … ] — class op on the
        #                             trigger (or a `to:` selector scoped to the root)
        #   * hide:/show: true      — hide/show the target while pending
        #   * text: "Saving…"       — swap the trigger's innerHTML while pending
        #   * to: :root / "sel"     — target the ops at the root or a selector
        # checked: :keep is optimistic-ONLY (a native flip has no settle-revert
        # meaning). The trigger/root also always carry `data-reactive-busy` for the
        # whole pending window regardless of these hints, so an app styles a spinner
        # with `[data-reactive-busy] .spinner { display: block }` and zero Ruby; see
        # busy_on for scoped indicators.
        #   button(**on(:save, busy: "Saving…")) { "Save" }
        #   button(**on(:destroy, confirm: "Sure?", busy: { add_class: "opacity-50" })) { "Delete" }
        def on(action_name, event: "click", debounce: nil, throttle: nil, confirm: nil,
               window: false, once: false, outside: false, optimistic: nil, busy: nil,
               **params)
          reject_removed_on_kwargs!(action_name, params)
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
          attrs[:data][:reactive_optimistic_param] = pending_hint_json(optimistic, action_name, :optimistic) if optimistic
          attrs[:data][:reactive_busy_param] = pending_hint_json(busy, action_name, :busy) if busy
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

        # Value-conditional visibility (issue #180) — the x-show / data-show /
        # wire:show equivalent, entirely client-side, in ONE Ruby-native
        # conditions language. Spread onto the element to show/hide; declare an
        # if:/if_any:/unless: condition with where-style values, and the generic
        # controller toggles `hidden` from the fields' CURRENT values on every
        # input/change — no round trip, no token, no bespoke Stimulus controller.
        #
        # THE VALUE LANGUAGE (Phlex::Reactive::ShowConditions):
        #   Hash    = AND (multiple keys ANDed)          if: { a: "x", b: "y" }
        #   Array   = membership                          if: { size: %w[l xl] }
        #   Range   = threshold (10.. / ..10 / ...10 / 10..20)  if: { qty: 10.. }
        #   true/false = checkbox checked-state           if: { gift: true }
        #   nil     = blank                               if: { note: nil }
        #   unless: = negation (composes with if:/if_any:)
        #
        #   div(**reactive_show(unless: { mode: "off" }))          { "details" }
        #   div(**reactive_show(if: { size: %w[l xl] }))           { "surcharge" }
        #   div(**reactive_show(if: { qty: 10.. }))                { "bulk note" }
        #   # OR-of-AND — director OR (shareholder AND role == "individual"):
        #   div(**reactive_show(if_any: [
        #     { director: true },
        #     { shareholder: true, role: "individual" }
        #   ]))
        #
        # There is no expression surface — every term is a declared literal, so
        # the same default-deny posture as before. Everything normalizes to ONE
        # DNF wire attr (data-reactive-show='{"any":[[term,…],…]}').
        #
        # FIRST PAINT is computed for you: declare reactive_values (an instance
        # method returning { field => value }) and every binding whose fields are
        # all provided renders the correct initial `hidden:` server-side — no
        # per-section mirror method, no flash. An explicit `hidden:` always wins;
        # a per-call `values:` override merges over reactive_values.
        #
        # `disable: true` disables the section's OWNED controls while it is hidden
        # so a switched-away value never submits. `reactive_scope :form` lets
        # bindings use bare field symbols ([name="form[field]"] on the client).
        #
        # Scope: presentational only, strictly less powerful than the js ops — it
        # reads owned fields (#15 ownership) and toggles `hidden` (+ optionally
        # `disabled`) on owned elements. Extra attrs deep-merge over the binding
        # (mix), like reactive_field.
        def reactive_show(field = nil, **options)
          reject_legacy_show_surface!(field, options)

          conditions = options.slice(*SHOW_CONDITION_KEYS)
          disable = options.delete(:disable)
          values_override = options.delete(:values)
          attrs = options.except(*SHOW_CONDITION_KEYS)

          groups = Phlex::Reactive::ShowConditions.normalize(**conditions)
          data = { reactive_show: { "any" => groups }.to_json }
          data[:reactive_show_disable] = "true" if disable

          result = mix({ data: }, attrs)
          apply_first_paint_hidden(result, groups, values_override)
        end

        # Client-side option filtering for the searchable combobox (issue #163)
        # — the "preload + type to narrow" half of #72's keyboard nav, entirely
        # client-side. Spread onto the ROOT (mix with reactive_root); it names
        # the input whose value drives the filter and the option elements to
        # show/hide, and the generic controller toggles `hidden` on every
        # keystroke by substring-matching each option's haystack — no round
        # trip, no token, no bespoke per-feature controller:
        #
        #   div(**mix(reactive_root, reactive_filter(
        #     input:  "#exercise-search",
        #     option: "[role=option]",
        #     group:  "[data-filter-group]",   # optional: collapse empty group headers
        #     empty:  "#no-matches"            # optional: reveal when 0 match
        #   ))) { … }
        #
        # Each option's haystack is its `data-reactive-filter-text` attribute
        # (server-rendered — pack in synonyms/categories), falling back to the
        # option's own text. Matching is a case-folded substring test — a
        # DECLARED literal match, never an expression (no eval surface, the
        # reactive_show posture). `group:` hides any group element whose every
        # contained option is hidden; `empty:` reveals the no-matches node when
        # 0 options are visible. The client seeds at connect and re-syncs after
        # a morph; selectors resolve WITHIN this root only (#15 ownership).
        #
        # Filtering composes with reactive_listnav (Arrow/Enter/Escape skip
        # hidden options) and each option's own on(:select, …) trigger —
        # selection still round-trips as a signed action; only FILTERING is
        # local. Blank selectors raise: a dead binding must fail at render.
        def reactive_filter(input:, option:, group: nil, empty: nil)
          data = {
            reactive_filter_input: filter_selector!(:input, input),
            reactive_filter_option: filter_selector!(:option, option)
          }
          data[:reactive_filter_group] = filter_selector!(:group, group) if group
          data[:reactive_filter_empty] = filter_selector!(:empty, empty) if empty

          { data: }
        end

        # STANDALONE combobox keyboard navigation (issue #163) — the same
        # Arrow/Enter/Escape wiring `on(…, listnav:)` appends, without the
        # dispatch descriptor. A preload-and-filter combobox input fires NO
        # action (filtering is pure client), so it can't carry on(); spread
        # this onto the input instead:
        #
        #   input(id: "search", type: "search", **reactive_listnav("[role=option]"))
        #
        # Arrow keys move the client-side highlight among the (visible) options,
        # Enter picks the highlighted one by clicking its own reactive trigger
        # (selection stays a signed action), Escape clears. Combine with other
        # attrs via mix so a caller's data-action token-joins, not clobbers.
        def reactive_listnav(option_selector = "[role=option]")
          {
            data: {
              action: LISTNAV_ACTIONS.join(" "),
              reactive_listnav_option_param: filter_selector!(:selector, option_selector)
            }
          }
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
        #     "#advanced-tab"   => "advanced",          # equals
        #     "#advanced-panel" => "advanced",
        #     "#premium-note"   => %w[gold platinum]))) # membership
        #
        # Same posture as mirror: — opt-in and declared, never implicit (a plain
        # reactive_show stays root-isolated); targets are SINGLE ID SELECTORS
        # only, enforced here at declare time AND warn-and-skipped by the client
        # interpreter (two-sided default-deny); the value uses the same where-
        # style conditions vocabulary (scalar/Array/Range, no expressions); and
        # the toggle is `hidden` only — no innerHTML, no attribute freedom. The
        # FIELD read stays owned (#15): you can only drive outside visibility from
        # a field this root owns. A target id not on the page is silently skipped
        # (an unrendered tab pane is normal). A target value is positive-only (no
        # per-target unless:) — express "not X" as a membership Array over the
        # remaining options.
        #
        # ONE call per root. Phlex `mix` space-joins duplicate STRING data
        # values, so a second call's JSON would concatenate into an unparseable
        # attr and the client would drop BOTH maps (it warns when that
        # happens). Several fields therefore go in ONE call via the hash form:
        #
        #   reactive_show_targets(mode: { "#advanced-tab" => "advanced" },
        #                         kind: { "#premium-note" => %w[gold platinum] })
        def reactive_show_targets(field, targets = nil)
          field_maps = targets.nil? ? field : { field => targets }
          unless field_maps.is_a?(Hash) && field_maps.any?
            raise ArgumentError,
              "reactive_show_targets needs at least one target " \
              "(:field, \"#id\" => value), got #{field_maps.inspect}"
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

        # The conditions-language kwargs (issue #180): if:/if_any:/unless: —
        # compiled by Phlex::Reactive::ShowConditions into the DNF wire. The ONE
        # vocabulary; there are no predicate kwargs any more.
        SHOW_CONDITION_KEYS = %i[if if_any unless].freeze

        # The removed 0.9.5 surface (issue #180 clean break): each of these
        # kwargs — and a positional field — now raises a GUIDED error printing
        # the if:/if_any:/unless: rewrite. Kept only to detect the legacy call
        # shape; nothing here reaches the wire.
        LEGACY_SHOW_PREDICATE_KEYS = %i[equals not in gte gt lte lt].freeze
        LEGACY_SHOW_CONNECTIVE_KEYS = %i[all any].freeze

        private

        # A reactive_filter/reactive_listnav selector, validated non-blank and
        # stringified (issue #163). A blank selector is a dead binding — the
        # client would silently match nothing — so it fails loudly at render,
        # like reactive_show's predicate validation.
        def filter_selector!(name, value)
          selector = value.to_s
          if selector.strip.empty?
            raise ArgumentError,
              "reactive_filter/reactive_listnav #{name}: needs a CSS selector, got #{value.inspect}"
          end

          selector
        end

        # Normalize + validate ONE field's target map (issue #180): each key a
        # single id selector (loud raise — the declare-time half of the two-sided
        # default-deny), each value a where-style condition value (scalar/Array/
        # Range) that compiles to ONE DNF group (terms ANDed). Shared by both
        # reactive_show_targets call forms.
        def normalize_show_target_map(field, targets)
          unless targets.is_a?(Hash) && targets.any?
            raise ArgumentError,
              "reactive_show_targets(#{field.inspect}) needs at least one target " \
              "(\"#id\" => value), got #{targets.inspect}"
          end

          targets.to_h do |selector, value|
            selector = selector.to_s
            unless selector.match?(DSL::MIRROR_ID_SELECTOR)
              raise ArgumentError,
                "reactive_show_targets(#{field.inspect}) target #{selector.inspect} must be a single " \
                "ID selector (\"#id\") — cross-root visibility is id-allowlisted, like mirror: (#159)"
            end
            if value.is_a?(Hash)
              raise ArgumentError,
                "reactive_show_targets(#{field.inspect}) target #{selector.inspect}: the { equals: ... } " \
                "predicate form was removed — pass a bare value (#{selector.inspect} => \"advanced\", " \
                "=> %w[a b] for a set, => 10.. for a threshold)"
            end

            # A target compiles to ONE group: the field-vs-value condition.
            groups = Phlex::Reactive::ShowConditions.normalize(if: { field => value })
            [selector, groups.first]
          end
        end

        # Reject the removed 0.9.5 reactive_show surface (issue #180 clean break)
        # with a GUIDED error printing the if:/if_any:/unless: rewrite. A
        # positional field, a predicate kwarg (equals:/not:/in:/gte:/…), or a
        # connective (all:/any:) all land here before any conditions parsing.
        def reject_legacy_show_surface!(field, options)
          unless field.nil?
            raise ArgumentError,
              "reactive_show no longer takes a positional field — the conditions language is " \
              "keyword-only: reactive_show(if: { #{field}: <value> }) (a Range is a threshold, " \
              "an Array is a set, unless: negates). See the 0.10 upgrade notes."
          end

          if (pred = options.keys & LEGACY_SHOW_PREDICATE_KEYS).any?
            raise ArgumentError,
              "reactive_show(#{pred.first}: ...) was removed — use the conditions language: " \
              "reactive_show(if: { field: value }). equals:/not: → if:/unless:, in: → an Array value, " \
              "gte:/gt:/lte:/lt: → a Range value (10.., ..10, ...10)."
          end
          if (conn = options.keys & LEGACY_SHOW_CONNECTIVE_KEYS).any?
            replacement = conn.first == :all ? "if: { … }" : "if_any: [{ … }, { … }]"
            raise ArgumentError,
              "reactive_show(#{conn.first}: [...]) was removed — use #{replacement}. " \
              "all: → if: (one AND group); any: → if_any: (OR of AND groups). Terms are now " \
              "field => value pairs, not { field:, equals: } hashes."
          end
        end

        # Compute the first-paint `hidden:` from reactive_values (issue #180) so
        # the author never restates the predicate as a Ruby mirror method. Fires
        # only when EVERY field the binding references is provided (by
        # reactive_values, merged under a per-call `values:` override); otherwise
        # the attrs are returned untouched. An explicit `hidden:` in the caller's
        # attrs always wins (it survives the mix, so this is a no-op then).
        def apply_first_paint_hidden(attrs, groups, values_override)
          return attrs if attrs.key?(:hidden)

          provided = show_values(values_override)
          return attrs if provided.nil?

          referenced = Phlex::Reactive::ShowConditions.fields(groups)
          return attrs unless referenced.all? { provided.key?(it) }

          visible = Phlex::Reactive::ShowConditions.match?(groups, provided)
          attrs.merge(hidden: !visible)
        end

        # The { field => current-string-value } map the first-paint evaluator
        # reads: reactive_values (if the component declares it) merged under a
        # per-call values: override, both stringified the way the client reads a
        # field (checkbox → "true"/"false", nil → ""). nil when neither source
        # exists — first paint then no-ops (no flash guarantee is the author's,
        # exactly as before).
        def show_values(values_override)
          base = respond_to?(:reactive_values) ? reactive_values : nil
          return nil if base.nil? && values_override.nil?

          merged = {}
          merged.merge!(base) if base
          merged.merge!(values_override) if values_override
          merged.to_h { |name, value| [name.to_s, show_value_string(value)] }
        end

        # Stringify a reactive_values entry the way the client's #showFieldValue
        # reports the live field: a boolean is the checkbox checked-state string,
        # nil is blank, everything else is to_s.
        def show_value_string(value)
          case value
          when true then "true"
          when false then "false"
          when nil then ""
          else value.to_s
          end
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

        # The removed on() pending-state kwargs (issue #181). loading:/disable_with:
        # collapsed into busy:; listnav: into the standalone reactive_listnav.
        # They now land in **params, so catch them there and raise a guided error
        # showing the rewrite — a clean break (pre-1.0), not a silent shim that
        # would ship a stale call to the browser wrong.
        REMOVED_ON_KWARGS = {
          disable_with: 'busy: "…" (String shorthand for { disable: true, text: "…" })',
          loading: "busy: { disable:, add_class:, text:, to: } (same keys as optimistic:)",
          listnav: "reactive_listnav — mix(on(:search, event: \"input\"), reactive_listnav)"
        }.freeze

        # The unified pending-state hint vocabulary (issue #181): the js.* op names
        # shared by optimistic: and busy:, plus disable:/to:. checked: :keep is
        # optimistic-ONLY (a native control flip has no settle-revert meaning).
        PENDING_CLASS_OPS = %w[toggle_class add_class remove_class].freeze

        private_constant :REMOVED_ON_KWARGS, :PENDING_CLASS_OPS

        def reject_removed_on_kwargs!(action_name, params)
          removed = params.keys & REMOVED_ON_KWARGS.keys
          return if removed.empty?

          key = removed.first
          raise ArgumentError,
            "on(#{action_name.inspect}) #{key}: was removed in issue #181 — use #{REMOVED_ON_KWARGS[key]}"
        end

        # Normalize + validate a pending-state hint (issue #181), returning its
        # JSON wire form. ONE vocabulary + ONE normalizer for both optimistic: (kind
        # :optimistic, reverts on FAILURE) and busy: (kind :busy, reverts on
        # SETTLE); they differ only in client lifecycle, not in shape. The String
        # shorthand `busy: "Saving…"` expands to { disable: true, text: … }. `to:`
        # resolves through the SAME JS.normalize_target the js op builder uses (a
        # :root sentinel or a verbatim CSS selector). checked: :keep is accepted
        # only for :optimistic. An unknown key, a bad value, or the wrong type
        # raises — a dead hint fails loudly at render, never silently on the client.
        def pending_hint_json(source, action_name, kind)
          source = { disable: true, text: source } if kind == :busy && source.is_a?(String)
          unless source.is_a?(Hash)
            raise ArgumentError,
              "on(#{action_name.inspect}) #{kind}: must be a #{"String or " if kind == :busy}Hash of visual " \
              "hints (e.g. { disable: true, text: \"Saving…\" }), got #{source.class}"
          end

          hint = {}
          source.each do |key, value|
            case key.to_s
            when *PENDING_CLASS_OPS
              hint[key.to_s] = Array(value).map(&:to_s)
            when "hide", "show", "disable"
              hint[key.to_s] = value ? true : false
            when "text"
              hint["text"] = value.to_s
            when "to"
              hint["to"] = Phlex::Reactive::JS.normalize_target(value)
            when "checked"
              hint["checked"] = pending_checked!(value, action_name, kind)
            else
              raise ArgumentError,
                "on(#{action_name.inspect}) got an unknown #{kind} hint #{key.inspect} — supported: " \
                "add_class/remove_class/toggle_class, hide:, show:, disable:, text:, to:" \
                "#{", checked: :keep" if kind == :optimistic}"
            end
          end

          hint.to_json
        end

        # checked: :keep flips a native checkbox/radio and reverts on failure — it
        # only makes sense for optimistic: (a settle-revert busy: hint has no native
        # control to keep). Reject it for :busy, and reject any value but :keep.
        def pending_checked!(value, action_name, kind)
          if kind != :optimistic
            raise ArgumentError,
              "on(#{action_name.inspect}) #{kind}: does not support checked: — the native-control " \
              "flip is an optimistic-only hint (it reverts on failure, not on settle)"
          end
          unless value.to_s == "keep"
            raise ArgumentError,
              "on(#{action_name.inspect}) optimistic checked: only supports :keep " \
              "(flip the native control, revert on failure), got #{value.inspect}"
          end

          "keep"
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
