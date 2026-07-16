# frozen_string_literal: true

module Claims
  class ConversationMessageGrid < ApplicationRecord
    self.table_name = "claims.v_conversation_message_grid"
    self.primary_key = "conversation_message_id"

    def readonly?
      true
    end
  end
end
