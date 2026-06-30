# frozen_string_literal: true

# Server-side registry for ReactiveModalComponent content. The client carries
# only the modal key + open flag (signed); the title/body/code live here.
module DocModals
  ENTRIES = {
    'signed-identity' => {
      title: "What's in the signed token?",
      lexer: :ruby,
      code: <<~RUBY
        # The DOM carries a MessageVerifier-signed identity — never raw state:
        { "c" => "TodoItemComponent", "gid" => "gid://app/Todo/42" }   # record-backed
        { "c" => "CounterComponent",  "s" => { "count" => 7 } }        # state-backed

        # Tampering the class, record, or state fails verification → 400.
      RUBY
    }
  }.freeze

  def self.find(key)
    ENTRIES[key.to_s]
  end
end
