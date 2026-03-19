# app/services/claims/sessions/update.rb
module Claims
  module Sessions
    class Update
      Result = Struct.new(:session)

      def self.call(session:, submitter_id:, submitted_at:)
        new(session: session, submitter_id: submitter_id, submitted_at: submitted_at).call
      end

      def initialize(session:, submitter_id:, submitted_at:)
        @session = session
        @submitter_id = submitter_id.presence
        @submitted_at = submitted_at.presence
      end

      def call
        if @submitter_id.present? ^ @submitted_at.present?
          raise ArgumentError, "submitter_id and submitted_at must either both be provided or both be blank"
        end

        normalized_submitted_at = @submitted_at.present? ? Time.zone.parse(@submitted_at.to_s) : nil

        attrs = {
          submitter_id: @submitter_id,
          submitted_at: normalized_submitted_at
        }

        attrs[:status] =
          if @session.status == "CLOSED"
            "CLOSED"
          elsif normalized_submitted_at.present?
            "OPENANDSUBMITTED"
          else
            "OPENBUTNOTSUBMITTED"
          end

        @session.update!(attrs)
        Result.new(@session)
      end
    end
  end
end
