# app/services/claims/sessions/create.rb
module Claims
  module Sessions
    class Create
      Result = Struct.new(:session)

      def self.call(contractor_id:, submitter_id: nil, submitted_at: nil)
        new(contractor_id: contractor_id, submitter_id: submitter_id, submitted_at: submitted_at).call
      end

      def initialize(contractor_id:, submitter_id:, submitted_at:)
        @contractor_id = contractor_id
        @submitter_id = submitter_id.presence
        @submitted_at = submitted_at.presence
      end

      def call
        now = Time.zone.now

        Rails.logger.info("[CLAIMS][SESSIONS_CREATE] contractor_id=#{@contractor_id} submitter_id=#{@submitter_id} submitted_at=#{@submitted_at} starting create")

        if @submitter_id.present? ^ @submitted_at.present?
          raise ArgumentError, "submitter_id and submitted_at must either both be provided or both be blank"
        end

        normalized_submitted_at = @submitted_at.present? ? Time.zone.parse(@submitted_at.to_s) : nil

        session = ::Claims::Session.create!(
          contractor_id: @contractor_id,
          submitter_id: @submitter_id,
          status: normalized_submitted_at.present? ? "OPENANDSUBMITTED" : "OPENBUTNOTSUBMITTED",
          submitted_at: normalized_submitted_at,
          created_at: now,
          updated_at: now
        )

        Result.new(session)
      end
    end
  end
end
